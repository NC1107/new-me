// Package anthropic is the small slice of the Claude Messages API the server uses: one call
// that forces a JSON answer through a tool schema, and one that returns plain text. Nothing
// here is required for the app to work; a server without a key never builds a client.
package anthropic

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	// DefaultBaseURL is the public API host.
	DefaultBaseURL = "https://api.anthropic.com"
	// Model is the one model every feature uses.
	Model = "claude-sonnet-4-6"
	// version is the API version header; the Messages API has used this value since launch.
	version = "2023-06-01"

	defaultTimeout = 30 * time.Second
	// maxResponseBytes bounds what is read back, since the answer is a few hundred tokens.
	maxResponseBytes = 1 << 20
)

// ErrUpstream wraps every failure to get a usable answer: transport, status or shape.
var ErrUpstream = errors.New("anthropic: upstream failure")

// Client calls the Messages API.
type Client struct {
	Key     string
	BaseURL string
	HTTP    *http.Client
}

// New builds a client; an empty baseURL means the public API.
func New(key, baseURL string) *Client {
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	return &Client{Key: key, BaseURL: baseURL, HTTP: &http.Client{Timeout: defaultTimeout}}
}

// Block is one piece of a user message: text, or an image given as base64.
type Block struct {
	Text      string
	MediaType string
	ImageB64  string
}

func (b Block) wire() map[string]any {
	if b.ImageB64 != "" {
		return map[string]any{"type": "image", "source": map[string]any{
			"type": "base64", "media_type": b.MediaType, "data": b.ImageB64}}
	}
	return map[string]any{"type": "text", "text": b.Text}
}

// Tool is a function the model must answer through.
type Tool struct {
	Name        string
	Description string
	Schema      map[string]any
}

// Turn is one earlier message of a conversation, as plain text.
type Turn struct {
	// Role is "user" or "assistant".
	Role string
	Text string
}

// Request is one call: a single user message, or a whole conversation in Turns.
type Request struct {
	System string
	User   []Block
	// Turns, when set, is sent instead of User and must end with a user turn.
	Turns     []Turn
	MaxTokens int
	// Tool, when set, is forced as the only way to answer.
	Tool *Tool
	// Tools, when set, are offered and the model chooses whether to call them. Use with
	// Messages; it is ignored when Tool is set.
	Tools []Tool
	// Messages, when set, is sent instead of User and Turns. It carries tool calls and results.
	Messages []Message
}

// Content is one block of a Message: text, a tool call the model made, or the result of one.
type Content struct {
	// Type is "text", "tool_use" or "tool_result".
	Type string
	Text string
	// ID and Name identify a tool call, and ID is echoed as ToolUseID on its result.
	ID    string
	Name  string
	Input json.RawMessage
	// ToolUseID, Result and IsError describe a tool_result.
	ToolUseID string
	Result    string
	IsError   bool
}

// Message is one turn of a conversation made of content blocks.
type Message struct {
	Role    string
	Content []Content
}

func (c Content) wire() map[string]any {
	switch c.Type {
	case "tool_use":
		input := c.Input
		if len(input) == 0 {
			input = json.RawMessage("{}")
		}
		return map[string]any{"type": "tool_use", "id": c.ID, "name": c.Name, "input": input}
	case "tool_result":
		out := map[string]any{"type": "tool_result", "tool_use_id": c.ToolUseID, "content": c.Result}
		if c.IsError {
			out["is_error"] = true
		}
		return out
	}
	return map[string]any{"type": "text", "text": c.Text}
}

type response struct {
	Content []struct {
		Type  string          `json:"type"`
		Text  string          `json:"text"`
		ID    string          `json:"id"`
		Name  string          `json:"name"`
		Input json.RawMessage `json:"input"`
	} `json:"content"`
	StopReason string `json:"stop_reason"`
}

func (c *Client) call(ctx context.Context, req Request) (response, error) {
	var out response
	messages := []map[string]any{}
	switch {
	case len(req.Messages) > 0:
		for _, m := range req.Messages {
			blocks := make([]map[string]any, len(m.Content))
			for i, b := range m.Content {
				blocks[i] = b.wire()
			}
			messages = append(messages, map[string]any{"role": m.Role, "content": blocks})
		}
	case len(req.Turns) > 0:
		for _, t := range req.Turns {
			messages = append(messages, map[string]any{"role": t.Role, "content": t.Text})
		}
	default:
		blocks := make([]map[string]any, len(req.User))
		for i, b := range req.User {
			blocks[i] = b.wire()
		}
		messages = append(messages, map[string]any{"role": "user", "content": blocks})
	}
	body := map[string]any{
		"model":      Model,
		"max_tokens": req.MaxTokens,
		"system":     req.System,
		"messages":   messages,
	}
	if req.Tool != nil {
		body["tools"] = []map[string]any{{
			"name": req.Tool.Name, "description": req.Tool.Description, "input_schema": req.Tool.Schema}}
		body["tool_choice"] = map[string]any{"type": "tool", "name": req.Tool.Name}
	} else if len(req.Tools) > 0 {
		tools := make([]map[string]any, len(req.Tools))
		for i, t := range req.Tools {
			tools[i] = map[string]any{"name": t.Name, "description": t.Description, "input_schema": t.Schema}
		}
		body["tools"] = tools
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return out, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/v1/messages", bytes.NewReader(raw))
	if err != nil {
		return out, err
	}
	httpReq.Header.Set("x-api-key", c.Key)
	httpReq.Header.Set("anthropic-version", version)
	httpReq.Header.Set("content-type", "application/json")
	resp, err := c.HTTP.Do(httpReq)
	if err != nil {
		return out, fmt.Errorf("%w: %v", ErrUpstream, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return out, fmt.Errorf("%w: %v", ErrUpstream, err)
	}
	if resp.StatusCode != http.StatusOK {
		return out, fmt.Errorf("%w: status %d", ErrUpstream, resp.StatusCode)
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return out, fmt.Errorf("%w: unreadable answer", ErrUpstream)
	}
	return out, nil
}

// ToolInput returns the arguments the model passed to the forced tool.
func (c *Client) ToolInput(ctx context.Context, req Request) (json.RawMessage, error) {
	if req.Tool == nil {
		return nil, errors.New("anthropic: ToolInput needs a tool")
	}
	resp, err := c.call(ctx, req)
	if err != nil {
		return nil, err
	}
	for _, block := range resp.Content {
		if block.Type == "tool_use" && len(block.Input) > 0 {
			return block.Input, nil
		}
	}
	return nil, fmt.Errorf("%w: no tool call in the answer", ErrUpstream)
}

// Text returns the model's plain-text answer.
func (c *Client) Text(ctx context.Context, req Request) (string, error) {
	resp, err := c.call(ctx, req)
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	for _, block := range resp.Content {
		if block.Type == "text" {
			sb.WriteString(block.Text)
		}
	}
	if strings.TrimSpace(sb.String()) == "" {
		return "", fmt.Errorf("%w: empty answer", ErrUpstream)
	}
	return strings.TrimSpace(sb.String()), nil
}

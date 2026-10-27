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

// Request is one single-turn call.
type Request struct {
	System    string
	User      []Block
	MaxTokens int
	// Tool, when set, is forced as the only way to answer.
	Tool *Tool
}

type response struct {
	Content []struct {
		Type  string          `json:"type"`
		Text  string          `json:"text"`
		Input json.RawMessage `json:"input"`
	} `json:"content"`
	StopReason string `json:"stop_reason"`
}

func (c *Client) call(ctx context.Context, req Request) (response, error) {
	var out response
	blocks := make([]map[string]any, len(req.User))
	for i, b := range req.User {
		blocks[i] = b.wire()
	}
	body := map[string]any{
		"model":      Model,
		"max_tokens": req.MaxTokens,
		"system":     req.System,
		"messages":   []map[string]any{{"role": "user", "content": blocks}},
	}
	if req.Tool != nil {
		body["tools"] = []map[string]any{{
			"name": req.Tool.Name, "description": req.Tool.Description, "input_schema": req.Tool.Schema}}
		body["tool_choice"] = map[string]any{"type": "tool", "name": req.Tool.Name}
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

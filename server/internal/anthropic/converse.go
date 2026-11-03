package anthropic

import (
	"context"
	"fmt"
	"strings"
)

// Reply is the model's answer to a conversation that offered tools: the text it wrote and the
// calls it wants made.
type Reply struct {
	Text  string
	Calls []Content
	// Blocks is the whole assistant message, to append to the conversation before the results.
	Blocks []Content
}

// Converse sends Messages with Tools offered and returns what the model wrote and called.
func (c *Client) Converse(ctx context.Context, req Request) (Reply, error) {
	resp, err := c.call(ctx, req)
	if err != nil {
		return Reply{}, err
	}
	var out Reply
	var sb strings.Builder
	for _, b := range resp.Content {
		switch b.Type {
		case "text":
			sb.WriteString(b.Text)
			out.Blocks = append(out.Blocks, Content{Type: "text", Text: b.Text})
		case "tool_use":
			call := Content{Type: "tool_use", ID: b.ID, Name: b.Name, Input: b.Input}
			out.Calls = append(out.Calls, call)
			out.Blocks = append(out.Blocks, call)
		}
	}
	out.Text = strings.TrimSpace(sb.String())
	if out.Text == "" && len(out.Calls) == 0 {
		return Reply{}, fmt.Errorf("%w: empty answer", ErrUpstream)
	}
	return out, nil
}

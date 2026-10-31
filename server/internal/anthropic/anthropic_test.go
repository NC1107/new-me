package anthropic

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func serve(t *testing.T, got *map[string]any) *Client {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, got)
		_, _ = w.Write([]byte(`{"content":[{"type":"text","text":" hi "}]}`))
	}))
	t.Cleanup(srv.Close)
	return New("key", srv.URL)
}

func TestTurnsAreSentAsTheWholeConversation(t *testing.T) {
	var body map[string]any
	c := serve(t, &body)
	out, err := c.Text(context.Background(), Request{System: "s", MaxTokens: 10, Turns: []Turn{
		{Role: "user", Text: "a"}, {Role: "assistant", Text: "b"}, {Role: "user", Text: "c"},
	}})
	if err != nil || out != "hi" {
		t.Fatalf("Text = %q, %v", out, err)
	}
	messages := body["messages"].([]any)
	if len(messages) != 3 {
		t.Fatalf("messages = %v", messages)
	}
	last := messages[2].(map[string]any)
	if last["role"] != "user" || last["content"] != "c" {
		t.Fatalf("last message = %v", last)
	}
}

func TestASingleUserMessageStillGoesAsBlocks(t *testing.T) {
	var body map[string]any
	c := serve(t, &body)
	if _, err := c.Text(context.Background(), Request{MaxTokens: 10, User: []Block{{Text: "x"}}}); err != nil {
		t.Fatal(err)
	}
	content := body["messages"].([]any)[0].(map[string]any)["content"].([]any)
	if content[0].(map[string]any)["type"] != "text" {
		t.Fatalf("content = %v", content)
	}
}

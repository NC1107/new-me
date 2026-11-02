package anthropic

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestConverseOffersToolsAndReturnsCalls(t *testing.T) {
	var body map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &body)
		_, _ = w.Write([]byte(`{"content":[{"type":"text","text":" Sure "},{"type":"tool_use","id":"toolu_1","name":"remember_fact","input":{"text":"x"}}]}`))
	}))
	t.Cleanup(srv.Close)

	reply, err := New("key", srv.URL).Converse(context.Background(), Request{MaxTokens: 10,
		Tools: []Tool{{Name: "remember_fact", Description: "d", Schema: map[string]any{"type": "object"}}},
		Messages: []Message{
			{Role: "user", Content: []Content{{Type: "text", Text: "hi"}}},
			{Role: "assistant", Content: []Content{{Type: "tool_use", ID: "toolu_0", Name: "remember_fact", Input: json.RawMessage(`{"text":"y"}`)}}},
			{Role: "user", Content: []Content{{Type: "tool_result", ToolUseID: "toolu_0", Result: "ok", IsError: true}}},
		}})
	if err != nil {
		t.Fatal(err)
	}
	if reply.Text != "Sure" || len(reply.Calls) != 1 || reply.Calls[0].ID != "toolu_1" || string(reply.Calls[0].Input) != `{"text":"x"}` || len(reply.Blocks) != 2 {
		t.Fatalf("reply = %+v", reply)
	}
	if body["tool_choice"] != nil || len(body["tools"].([]any)) != 1 {
		t.Fatalf("tools were not offered freely: %v", body)
	}
	last := body["messages"].([]any)[2].(map[string]any)["content"].([]any)[0].(map[string]any)
	if last["type"] != "tool_result" || last["tool_use_id"] != "toolu_0" || last["is_error"] != true {
		t.Fatalf("tool result = %v", last)
	}
}

func TestConverseRejectsAnEmptyAnswer(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"content":[]}`))
	}))
	t.Cleanup(srv.Close)
	_, err := New("key", srv.URL).Converse(context.Background(), Request{MaxTokens: 10, Turns: []Turn{{Role: "user", Text: "hi"}}})
	if err == nil {
		t.Fatal("expected an upstream error")
	}
}

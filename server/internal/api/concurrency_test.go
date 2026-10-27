package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"sync"
	"testing"
	"time"
)

// call is a request safe to make from a goroutine: it reports instead of failing the test.
func (h *harness) call(method, path, token string, body any) (int, error) {
	raw, err := json.Marshal(body)
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequest(method, h.http.URL+path, bytes.NewReader(raw))
	if err != nil {
		return 0, err
	}
	req.Header.Set("X-App-Key", testAppKey)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := h.http.Client().Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}

func TestSimultaneousRetriesOfOneLogStoreItOnce(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	body := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 10}

	const attempts = 8
	statuses := make(chan int, attempts)
	var wg sync.WaitGroup
	for range attempts {
		wg.Add(1)
		go func() {
			defer wg.Done()
			status, err := h.call(http.MethodPost, "/api/logs", nick.Token, body)
			if err != nil {
				t.Errorf("post: %v", err)
			}
			statuses <- status
		}()
	}
	wg.Wait()
	close(statuses)

	created := 0
	for status := range statuses {
		switch status {
		case http.StatusCreated:
			created++
		case http.StatusOK:
		default:
			t.Errorf("unexpected status %d", status)
		}
	}
	if created != 1 {
		t.Fatalf("%d requests reported creating the entry, want exactly 1", created)
	}
	if h.get("/api/today", nick.Token).num("quests.1.actual") != 10 {
		t.Fatal("the entry must count once")
	}
}

// A health push and log writes racing on one day must leave the stored score equal to a fresh
// rescore of the final inputs, which is what the per-day lock exists to guarantee.
func TestRacingWritesLeaveTheStoredScoreConsistent(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "steps", 100).expect(http.StatusOK)

	var wg sync.WaitGroup
	for i := range 6 {
		wg.Add(2)
		go func() {
			defer wg.Done()
			_, err := h.call(http.MethodPost, "/api/logs", nick.Token, obj{
				"clientOpId": h.opID(100 + i), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 5})
			if err != nil {
				t.Errorf("log: %v", err)
			}
		}()
		go func() {
			defer wg.Done()
			_, err := h.call(http.MethodPut, "/api/health/daily", nick.Token, obj{"items": []obj{
				healthReading("2026-11-02", "steps", float64(1000*(i+1)), h.clock.Now().Add(time.Duration(i)*time.Second))}})
			if err != nil {
				t.Errorf("health: %v", err)
			}
		}()
	}
	wg.Wait()

	var stored int
	if err := h.db.Pool.QueryRow(t.Context(),
		`SELECT base_points FROM day_scores WHERE user_id = $1 AND local_date = '2026-11-02'`, nick.ID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	fresh := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if fresh.num("day.basePoints") != stored {
		t.Fatalf("stored base %d, fresh rescore %d", stored, fresh.num("day.basePoints"))
	}
	if fresh.num("quests.1.actual") != 30 || fresh.num("quests.0.actual") != 6000 {
		t.Fatalf("final inputs = %s", fresh.Body)
	}
}

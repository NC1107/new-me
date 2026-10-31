package voice

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type fakeKokoro struct {
	calls atomic.Int32
	mu    sync.Mutex
	last  map[string]any
	fail  bool
	delay time.Duration
}

func (f *fakeKokoro) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.calls.Add(1)
	raw, _ := io.ReadAll(r.Body)
	f.mu.Lock()
	_ = json.Unmarshal(raw, &f.last)
	fail := f.fail
	input, _ := f.last["input"].(string)
	f.mu.Unlock()
	time.Sleep(f.delay)
	if r.URL.Path != "/v1/audio/speech" || fail {
		http.Error(w, "nope", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte("ID3-audio-of-" + input))
}

func newSynth(t *testing.T, f *fakeKokoro, voice string, speed float64, dir string) *Synth {
	srv := httptest.NewServer(f)
	t.Cleanup(srv.Close)
	return New(srv.URL, voice, speed, dir)
}

func TestSpeakSendsTheVoiceAndSpeedAndCachesTheLine(t *testing.T) {
	f := &fakeKokoro{}
	s := newSynth(t, f, "af_heart", 0.8, t.TempDir())
	a, err := s.Speak(context.Background(), "Breathe in")
	if err != nil || string(a) != "ID3-audio-of-Breathe in" {
		t.Fatalf("speak = %q, %v", a, err)
	}
	f.mu.Lock()
	sent := f.last
	f.mu.Unlock()
	if sent["voice"] != "af_heart" || sent["speed"] != 0.8 || sent["response_format"] != "mp3" {
		t.Fatalf("request = %v", sent)
	}
	again, err := s.Speak(context.Background(), "Breathe in")
	if err != nil || string(again) != string(a) || f.calls.Load() != 1 {
		t.Fatalf("second speak made %d calls, err %v", f.calls.Load(), err)
	}
	if _, ok := s.Cached("Breathe in"); !ok {
		t.Fatal("line should be cached")
	}
	if _, ok := s.Cached("Breathe out"); ok {
		t.Fatal("another line must not be cached")
	}
}

func TestTheCacheSurvivesARestartButNotAChangeOfVoiceOrSpeed(t *testing.T) {
	dir := t.TempDir()
	f := &fakeKokoro{}
	if _, err := newSynth(t, f, "af_heart", 0.8, dir).Speak(context.Background(), "Hello"); err != nil {
		t.Fatal(err)
	}
	if _, err := newSynth(t, f, "af_heart", 0.8, dir).Speak(context.Background(), "Hello"); err != nil || f.calls.Load() != 1 {
		t.Fatalf("restart made %d calls, err %v", f.calls.Load(), err)
	}
	if _, err := newSynth(t, f, "af_bella", 0.8, dir).Speak(context.Background(), "Hello"); err != nil || f.calls.Load() != 2 {
		t.Fatalf("new voice made %d calls, err %v", f.calls.Load(), err)
	}
	if _, err := newSynth(t, f, "af_heart", 0.9, dir).Speak(context.Background(), "Hello"); err != nil || f.calls.Load() != 3 {
		t.Fatalf("new speed made %d calls, err %v", f.calls.Load(), err)
	}
}

func TestAFailureIsNotCached(t *testing.T) {
	f := &fakeKokoro{fail: true}
	s := newSynth(t, f, "af_heart", 0.8, t.TempDir())
	if _, err := s.Speak(context.Background(), "Hello"); err == nil {
		t.Fatal("want an error")
	}
	f.mu.Lock()
	f.fail = false
	f.mu.Unlock()
	if _, err := s.Speak(context.Background(), "Hello"); err != nil {
		t.Fatalf("retry: %v", err)
	}
}

func TestAskingForTheSameNewLineAtOnceSynthesisesItOnce(t *testing.T) {
	f := &fakeKokoro{delay: 100 * time.Millisecond}
	s := newSynth(t, f, "af_heart", 0.8, t.TempDir())
	var wg sync.WaitGroup
	for range 5 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := s.Speak(context.Background(), "Together"); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if f.calls.Load() != 1 {
		t.Fatalf("calls = %d, want 1", f.calls.Load())
	}
}

func TestAnUnwritableCacheStillSpeaks(t *testing.T) {
	f := &fakeKokoro{}
	s := newSynth(t, f, "af_heart", 0.8, "/proc/nope/never")
	if _, err := s.Speak(context.Background(), "Hello"); err != nil {
		t.Fatal(err)
	}
}

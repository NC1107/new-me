// Package voice turns a line of text into speech through a self-hosted Kokoro sidecar
// (Kokoro-FastAPI, OpenAI-compatible) and keeps every result on disk, so a line is synthesised
// once however many times it is asked for.
package voice

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sync/singleflight"
)

const (
	// MaxRunes bounds one line; the longest bundled clip is about 250 characters.
	MaxRunes = 600
	// Format is what the sidecar renders. MP3 plays on iOS and in a browser alike.
	Format = "mp3"
	// ContentType is the MIME type of Format.
	ContentType = "audio/mpeg"

	timeout = 45 * time.Second
	// maxAudio guards memory against a misbehaving sidecar.
	maxAudio = 8 << 20
)

// Synth renders and caches speech.
type Synth struct {
	url      string
	voice    string
	speed    float64
	dir      string
	client   *http.Client
	inflight singleflight.Group
}

// New returns a synthesiser for the sidecar at baseURL. Lines are cached under dir.
func New(baseURL, voice string, speed float64, dir string) *Synth {
	return &Synth{url: baseURL, voice: voice, speed: speed, dir: dir, client: &http.Client{Timeout: timeout}}
}

// Key names a line for the cache: the voice and speed are part of it, so changing either
// re-renders instead of serving the old sound.
func (s *Synth) Key(text string) string {
	sum := sha256.Sum256(fmt.Appendf(nil, "%s\x00%g\x00%s\x00%s", s.voice, s.speed, Format, text))
	return hex.EncodeToString(sum[:])
}

func (s *Synth) path(key string) string { return filepath.Join(s.dir, key[:2], key+"."+Format) }

// Cached returns the stored audio for text, if there is any.
func (s *Synth) Cached(text string) ([]byte, bool) {
	b, err := os.ReadFile(s.path(s.Key(text)))
	return b, err == nil && len(b) > 0
}

// Speak returns the audio for text, from the cache or from the sidecar. Callers asking for the
// same new line at once share one synthesis.
func (s *Synth) Speak(ctx context.Context, text string) ([]byte, error) {
	if b, ok := s.Cached(text); ok {
		return b, nil
	}
	key := s.Key(text)
	v, err, _ := s.inflight.Do(key, func() (any, error) {
		// The shared call must outlive the first caller giving up.
		rctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), timeout)
		defer cancel()
		b, err := s.synthesize(rctx, text)
		if err != nil {
			return nil, err
		}
		s.store(key, b)
		return b, nil
	})
	if err != nil {
		return nil, err
	}
	return v.([]byte), nil
}

func (s *Synth) synthesize(ctx context.Context, text string) ([]byte, error) {
	body, err := json.Marshal(map[string]any{
		"model": "kokoro", "input": text, "voice": s.voice,
		"response_format": Format, "speed": s.speed,
	})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.url+"/v1/audio/speech", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("tts request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("tts status %d: %s", resp.StatusCode, msg)
	}
	audio, err := io.ReadAll(io.LimitReader(resp.Body, maxAudio+1))
	if err != nil {
		return nil, fmt.Errorf("tts read: %w", err)
	}
	if len(audio) == 0 || len(audio) > maxAudio {
		return nil, errors.New("tts returned no audio or too much")
	}
	return audio, nil
}

// store writes atomically so a reader never sees half a file. A cache that cannot be written
// only costs a re-synthesis, so failure is not an error.
func (s *Synth) store(key string, audio []byte) {
	path := s.path(key)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), "tmp-*")
	if err != nil {
		return
	}
	_, werr := tmp.Write(audio)
	cerr := tmp.Close()
	if werr != nil || cerr != nil || os.Rename(tmp.Name(), path) != nil {
		_ = os.Remove(tmp.Name())
	}
}

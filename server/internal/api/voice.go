package api

import (
	"log"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/nc1107/new-me/server/internal/voice"
)

type voiceRequest struct {
	Text string `json:"text"`
}

var (
	errVoiceDisabled = newErr(http.StatusNotFound, codeVoiceDisabled, "server voice is not set up on this server")
	errVoiceFailed   = newErr(http.StatusBadGateway, codeVoiceFailed, "could not make that line right now, try again later")
)

// handleVoice speaks a line in the class voice. A line heard before comes from the disk cache and
// costs no synthesis, so only new lines count against the person's hourly budget.
func (s *Server) handleVoice(w http.ResponseWriter, r *http.Request) {
	if s.voice == nil {
		fail(w, r, errVoiceDisabled)
		return
	}
	var req voiceRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	text := strings.TrimSpace(req.Text)
	if n := utf8.RuneCountInString(text); n < 1 || n > voice.MaxRunes || hasControlChars(text) {
		fail(w, r, invalid("text must be 1 to 600 characters without control characters"))
		return
	}
	audio, ok := s.voice.Cached(text)
	if !ok {
		c := callerFrom(r)
		if allowed, retry := s.voices.Allow(strconv.FormatInt(c.user.ID, 10)); !allowed {
			w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
			writeErr(w, http.StatusTooManyRequests, codeRateLimited, "too many new voice lines this hour, try again later")
			return
		}
		var err error
		if audio, err = s.voice.Speak(r.Context(), text); err != nil {
			if r.Context().Err() == nil {
				log.Printf("[NEWME] voice for user %d: %v", c.user.ID, err)
			}
			fail(w, r, errVoiceFailed)
			return
		}
	}
	w.Header().Set("Content-Type", voice.ContentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(audio)))
	// A line never changes for the same text, voice and speed, so the app may keep it.
	w.Header().Set("Cache-Control", "private, max-age=31536000, immutable")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(audio)
}

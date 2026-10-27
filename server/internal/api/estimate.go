package api

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/nc1107/new-me/server/internal/estimate"
)

type estimateRequest struct {
	Text      string `json:"text"`
	Image     string `json:"image"`
	MediaType string `json:"mediaType"`
}

var (
	errEstimateDisabled = newErr(http.StatusNotFound, codeEstimateDisabled, "meal estimates are not set up on this server")
	errEstimateFailed   = newErr(http.StatusBadGateway, codeEstimateFailed, "could not get an estimate right now, try again later")
)

// handleEstimateMeal asks Claude for the nutrition of a meal described in words or shown in a
// photo. Nothing is stored: the photo is forwarded and dropped, and the person confirms the
// numbers before anything reaches the meal log.
func (s *Server) handleEstimateMeal(w http.ResponseWriter, r *http.Request) {
	if s.estimator == nil {
		fail(w, r, errEstimateDisabled)
		return
	}
	var req estimateRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	text := strings.TrimSpace(req.Text)
	if n := utf8.RuneCountInString(text); n > estimate.MaxTextRunes || hasControlChars(text) {
		fail(w, r, invalid("text must be at most 500 characters without control characters"))
		return
	}
	hasImage := req.Image != ""
	if !hasImage && text == "" {
		fail(w, r, invalid("send text, or an image with its mediaType"))
		return
	}
	var image string
	if hasImage {
		var err error
		if image, err = estimate.ValidateImage(req.MediaType, req.Image); err != nil {
			if errors.Is(err, estimate.ErrImageTooLarge) {
				fail(w, r, newErr(http.StatusRequestEntityTooLarge, codeTooLarge, err.Error()))
				return
			}
			fail(w, r, invalid(err.Error()))
			return
		}
	}

	c := callerFrom(r)
	if ok, retry := s.estimates.Allow(strconv.FormatInt(c.user.ID, 10)); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
		writeErr(w, http.StatusTooManyRequests, codeRateLimited, "too many meal estimates this hour, try again later")
		return
	}

	var (
		est estimate.Estimate
		err error
	)
	if hasImage {
		est, err = s.estimator.FromImage(r.Context(), req.MediaType, image, text)
	} else {
		est, err = s.estimator.FromText(r.Context(), text)
	}
	if err != nil {
		if r.Context().Err() == nil {
			log.Printf("[NEWME] meal estimate for user %d: %v", c.user.ID, err)
		}
		fail(w, r, errEstimateFailed)
		return
	}
	writeJSON(w, http.StatusOK, est)
}

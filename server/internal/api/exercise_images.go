package api

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/static"
)

// imageCacheSeconds lets the app keep a photo for a month; photos only change with a release.
const imageCacheSeconds = 30 * 24 * 60 * 60

func exerciseImageURLs(e db.Exercise) []string {
	urls := make([]string, 0, len(e.Images))
	for i := range e.Images {
		urls = append(urls, "/api/exercises/"+e.Key+"/images/"+strconv.Itoa(i))
	}
	return urls
}

// handleExerciseImage serves one how-to photo of an exercise from the embedded files. It sits behind
// the app key and device token like every route; the app passes both headers when it loads a photo.
func (s *Server) handleExerciseImage(w http.ResponseWriter, r *http.Request) {
	n, err := strconv.Atoi(chi.URLParam(r, "n"))
	if err != nil || n < 0 {
		fail(w, r, errNoExercise)
		return
	}
	e, err := db.ExerciseByKey(r.Context(), s.db.Pool, callerFrom(r).user.ID, chi.URLParam(r, "key"))
	if errors.Is(err, db.ErrNotFound) || (err == nil && n >= len(e.Images)) {
		fail(w, r, errNoExercise)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	data, err := static.Exercises.ReadFile("exercises/" + e.Images[n])
	if err != nil {
		fail(w, r, errNoExercise)
		return
	}
	sum := sha256.Sum256(data)
	h := w.Header()
	h.Set("Content-Type", "image/jpeg")
	h.Set("Cache-Control", "private, max-age="+strconv.Itoa(imageCacheSeconds))
	h.Set("ETag", `"`+hex.EncodeToString(sum[:8])+`"`)
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(data))
}

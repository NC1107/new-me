package api

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"net/http"
	"strings"
	"time"
	"unicode"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

// Machine-readable error codes, the contract the app switches on.
const (
	codeUnauthorized     = "unauthorized"
	codeBadAppKey        = "bad_app_key"
	codeInvalidCode      = "invalid_code"
	codeForbidden        = "forbidden"
	codeNotFound         = "not_found"
	codeNameTaken        = "name_taken"
	codeColorTaken       = "color_taken"
	codeServerFull       = "server_full"
	codeSessionExists    = "session_exists"
	codeInitialized      = "server_initialized"
	codeDateClosed       = "date_closed"
	codeInvalidTimezone  = "invalid_timezone"
	codeInvalidRequest   = "invalid_request"
	codeInvalidJSON      = "invalid_json"
	codeTooLarge         = "payload_too_large"
	codeUpdateRequired   = "update_required"
	codeRateLimited      = "rate_limited"
	codeUnavailable      = "unavailable"
	codeInternal         = "internal"
	codeMethodNotAllowed = "method_not_allowed"
	codeABSDisabled      = "abs_disabled"
	codeABSLoginFailed   = "abs_login_failed"
	codeABSUnavailable   = "abs_unavailable"
	codeABSNotLinked     = "abs_not_linked"
	codeEstimateDisabled = "estimate_disabled"
	codeEstimateFailed   = "estimate_unavailable"
)

// httpError is a failure the caller can see. Handlers return it from transaction bodies so the
// transaction rolls back, then send it with fail.
type httpError struct {
	status int
	code   string
	msg    string
	// items carries per-item detail for batch endpoints.
	items []itemError
}

func (e *httpError) Error() string { return e.msg }

type itemError struct {
	Index int    `json:"index"`
	Code  string `json:"code"`
	Error string `json:"error"`
}

func newErr(status int, code, msg string) *httpError {
	return &httpError{status: status, code: code, msg: msg}
}

func invalid(msg string) *httpError {
	return newErr(http.StatusUnprocessableEntity, codeInvalidRequest, msg)
}

var errDateClosed = newErr(http.StatusUnprocessableEntity, codeDateClosed, "that day is closed for entries")

// writeJSON sends a JSON response with the given status.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// writeErr sends the error envelope {"error": msg, "code": code}.
func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]string{"error": msg, "code": code})
}

// fail sends err if it is an httpError and otherwise logs it and answers 500. A request whose
// context ended is not a server fault, so it is not logged as one.
func fail(w http.ResponseWriter, r *http.Request, err error) {
	var he *httpError
	if errors.As(err, &he) {
		body := map[string]any{"error": he.msg, "code": he.code}
		if he.items != nil {
			body["items"] = he.items
		}
		writeJSON(w, he.status, body)
		return
	}
	if !errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded) {
		log.Printf("[NEWME] %s %s (request %s): %v", r.Method, r.URL.Path, middleware.GetReqID(r.Context()), err)
	}
	writeErr(w, http.StatusInternalServerError, codeInternal, "server error")
}

// decodeJSON parses a request body into v. The body is already capped by the size middleware.
func decodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			return newErr(http.StatusRequestEntityTooLarge, codeTooLarge, "request body is too large")
		}
		return newErr(http.StatusBadRequest, codeInvalidJSON, "request body is not valid JSON for this endpoint")
	}
	return nil
}

// nullable tells a field that was absent from one sent as null, which PATCH uses to clear.
type nullable[T any] struct {
	Set   bool
	Value *T
}

func (n *nullable[T]) UnmarshalJSON(b []byte) error {
	n.Set = true
	if string(b) == "null" {
		n.Value = nil
		return nil
	}
	var v T
	if err := json.Unmarshal(b, &v); err != nil {
		return err
	}
	n.Value = &v
	return nil
}

// wireTime renders an instant as RFC 3339 in UTC.
func wireTime(t time.Time) string { return t.UTC().Format(time.RFC3339) }

func wireTimePtr(t *time.Time) *string {
	if t == nil {
		return nil
	}
	s := wireTime(*t)
	return &s
}

// round1 keeps one decimal, which is all NUMERIC(6,1) stores, so float sums print cleanly.
func round1(v float64) float64 { return math.Round(v*10) / 10 }

// parseDateParam reads an optional YYYY-MM-DD query value, defaulting to fallback.
func parseDateParam(raw string, fallback score.Date) (score.Date, *httpError) {
	if raw == "" {
		return fallback, nil
	}
	d, err := score.ParseDate(raw)
	if err != nil {
		return "", invalid("date must be YYYY-MM-DD")
	}
	return d, nil
}

// validColors are the accent ids the app offers. The schema only bounds the length, so the
// palette is enforced here.
var validColors = map[string]bool{
	"green": true, "sky": true, "violet": true, "amber": true, "rose": true, "teal": true,
}

// hasControlChars is true for text with a control character. NUL in particular makes Postgres
// fail the insert, which would otherwise surface as a server error.
func hasControlChars(s string) bool { return strings.ContainsFunc(s, unicode.IsControl) }

// cleanName trims and bounds a display name.
func cleanName(raw string) (string, *httpError) {
	name := strings.TrimSpace(raw)
	if n := len([]rune(name)); n < 1 || n > 40 || hasControlChars(name) {
		return "", invalid("name must be 1 to 40 characters without control characters")
	}
	return name, nil
}

func checkColor(color string) *httpError {
	if !validColors[color] {
		return invalid("color is not one of the available accents")
	}
	return nil
}

// loadZone resolves an IANA zone name from a request.
func loadZone(name string) (*time.Location, *httpError) {
	if name == "" || name == "Local" {
		return nil, newErr(http.StatusUnprocessableEntity, codeInvalidTimezone, "timezone must be an IANA zone name")
	}
	loc, err := time.LoadLocation(name)
	if err != nil {
		return nil, newErr(http.StatusUnprocessableEntity, codeInvalidTimezone, "unknown timezone")
	}
	return loc, nil
}

// titles are the display names of the quests.
var titles = map[string]string{
	db.QuestSteps:       "Steps",
	db.QuestPushups:     "Push-ups",
	db.QuestReading:     "Reading",
	db.QuestMealsLogged: "Meals",
	db.QuestProtein:     "Protein",
	db.QuestYoga:        "Yoga",
	db.QuestExercise:    "Exercise",
	db.QuestSleep:       "Sleep",
	db.QuestWater:       "Water",
	proposalCalories:    "Calories",
}

package api

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"log"
	"net"
	"net/http"
	"net/url"
	"runtime/debug"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/auth"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/ratelimit"
	"github.com/nc1107/new-me/server/internal/semver"
)

const (
	requestTimeout = 30 * time.Second
	maxBodyBytes   = 1 << 20
)

type ctxKey int

const callerKey ctxKey = iota

// caller is the authenticated user, the device that proved it and the user's zone.
type caller struct {
	user     db.User
	deviceID int64
	loc      *time.Location
}

func callerFrom(r *http.Request) caller { return r.Context().Value(callerKey).(caller) }

// recoverer turns a handler panic into the JSON 500 envelope instead of a dropped connection.
func recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			rec := recover()
			if rec == nil {
				return
			}
			if rec == http.ErrAbortHandler {
				panic(rec)
			}
			log.Printf("[NEWME] panic on %s %s: %v\n%s", r.Method, r.URL.Path, rec, debug.Stack())
			writeErr(w, http.StatusInternalServerError, codeInternal, "server error")
		}()
		next.ServeHTTP(w, r)
	})
}

// requestID tags the request and echoes the id so a user can quote it.
func requestID(next http.Handler) http.Handler {
	return middleware.RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Request-Id", middleware.GetReqID(r.Context()))
		next.ServeHTTP(w, r)
	}))
}

// limitBody caps what a handler can read from the request.
func limitBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		next.ServeHTTP(w, r)
	})
}

func secureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'")
		next.ServeHTTP(w, r)
	})
}

// devCORS lets a browser build served from localhost call the API. It answers the preflight
// itself, ahead of the app key check, because a preflight carries no custom headers.
func devCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" || !isLocalOrigin(origin) {
			next.ServeHTTP(w, r)
			return
		}
		h := w.Header()
		h.Set("Access-Control-Allow-Origin", origin)
		h.Add("Vary", "Origin")
		h.Set("Access-Control-Expose-Headers", "Retry-After, X-Request-Id")
		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			h.Set("Access-Control-Allow-Headers", "X-App-Key, Authorization, X-Client-Version, Content-Type")
			h.Set("Access-Control-Max-Age", "600")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isLocalOrigin(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return false
	}
	switch u.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return true
	}
	return false
}

// appKey rejects any request lacking the shared key with 403, never 401, so a rotated key
// cannot sign the app out. Health is exempt so the container healthcheck keeps working.
func (s *Server) appKey(next http.Handler) http.Handler {
	// Hashing first makes the compare constant-time regardless of the supplied length.
	want := sha256.Sum256([]byte(s.cfg.AppKey))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/api/health" {
			next.ServeHTTP(w, r)
			return
		}
		got := sha256.Sum256([]byte(r.Header.Get("X-App-Key")))
		if subtle.ConstantTimeCompare(got[:], want[:]) != 1 {
			writeErr(w, http.StatusForbidden, codeBadAppKey, "missing or invalid app key")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// clientVersion answers 426 to an app older than the configured minimum. Health and server
// info stay open so the app can still read the minimum and explain itself.
func (s *Server) clientVersion(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got := r.Header.Get("X-Client-Version")
		if got == "" || r.URL.Path == "/api/health" || r.URL.Path == "/api/server-info" {
			next.ServeHTTP(w, r)
			return
		}
		v, err := semver.Parse(got)
		if err != nil || v.Less(s.minClient) {
			writeJSON(w, http.StatusUpgradeRequired, map[string]string{
				"error":            "this version of the app is no longer supported, please update",
				"code":             codeUpdateRequired,
				"minClientVersion": s.cfg.MinClientVersion,
			})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// clientIP is the address the trusted proxy saw, or the TCP peer when there is no proxy chain.
func clientIP(r *http.Request) string {
	if ip := middleware.GetClientIP(r.Context()); ip != "" {
		return ip
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}

// limit answers 429 with Retry-After once the key's bucket is empty.
func limit(l *ratelimit.Limiter, key func(*http.Request) string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ok, retry := l.Allow(key(r))
			if !ok {
				seconds := max(1, int((retry+time.Second-1)/time.Second))
				w.Header().Set("Retry-After", strconv.Itoa(seconds))
				writeErr(w, http.StatusTooManyRequests, codeRateLimited, "too many requests, slow down")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func byClientIP(r *http.Request) string { return clientIP(r) }

func byDevice(r *http.Request) string { return strconv.FormatInt(callerFrom(r).deviceID, 10) }

// requireAuth resolves the bearer token to its user and device. Only a bad or revoked token is
// a 401; a database failure is a 500 so the app never signs out over a server fault.
func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeErr(w, http.StatusUnauthorized, codeUnauthorized, "missing or invalid token")
			return
		}
		user, deviceID, err := db.UserByTokenHash(r.Context(), s.db.Pool, auth.HashToken(token))
		if errors.Is(err, db.ErrNotFound) {
			writeErr(w, http.StatusUnauthorized, codeUnauthorized, "missing or invalid token")
			return
		}
		if err != nil {
			fail(w, r, err)
			return
		}
		user, err = db.SwitchTimezoneIfDue(r.Context(), s.db.Pool, user, s.now())
		if err != nil {
			fail(w, r, err)
			return
		}
		loc, err := user.Location()
		if err != nil {
			fail(w, r, err)
			return
		}
		ctx := context.WithValue(r.Context(), callerKey, caller{user: user, deviceID: deviceID, loc: loc})
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func bearerToken(r *http.Request) (string, bool) {
	const prefix = "Bearer "
	h := r.Header.Get("Authorization")
	if len(h) <= len(prefix) || h[:len(prefix)] != prefix {
		return "", false
	}
	return h[len(prefix):], true
}

// requireAdmin lets only the admin through.
func requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !callerFrom(r).user.IsAdmin {
			writeErr(w, http.StatusForbidden, codeForbidden, "admin only")
			return
		}
		next.ServeHTTP(w, r)
	})
}

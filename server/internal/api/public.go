package api

import (
	"net/http"

	"github.com/nc1107/new-me/server/internal/db"
)

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.health.ping(r, s.db); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable", "version": s.version})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": s.version})
}

// handleServerInfo is all a device sees before pairing: no user list, ever.
func (s *Server) handleServerInfo(w http.ResponseWriter, r *http.Request) {
	info, err := s.db.GetServerInfo(r.Context())
	if err != nil {
		fail(w, r, err)
		return
	}
	live, err := db.CountUsers(r.Context(), s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"name":             info.Name,
		"initialized":      info.Initialized,
		"joinOpen":         !info.Initialized || live < s.cfg.MaxUsers,
		"minClientVersion": s.cfg.MinClientVersion,
	})
}

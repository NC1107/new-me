package api

import (
	"context"
	"net/http"
	"slices"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

type seasonJSON struct {
	Name     string      `json:"name"`
	StartsOn score.Date  `json:"startsOn"`
	EndsOn   *score.Date `json:"endsOn"`
}

type boardDayJSON struct {
	Points  int  `json:"points"`
	Percent int  `json:"percent"`
	Counted bool `json:"counted"`
}

type pointsJSON struct {
	Points int `json:"points"`
}

type streakCountJSON struct {
	Current int `json:"current"`
}

type dayMarkJSON struct {
	Date    score.Date `json:"date"`
	Percent int        `json:"percent"`
	Counted bool       `json:"counted"`
	Rest    bool       `json:"rest"`
}

type boardUserJSON struct {
	ID       int64           `json:"id"`
	Name     string          `json:"name"`
	Color    string          `json:"color"`
	Today    boardDayJSON    `json:"today"`
	Week     pointsJSON      `json:"week"`
	Season   pointsJSON      `json:"season"`
	Streak   streakCountJSON `json:"streak"`
	Last7    []dayMarkJSON   `json:"last7"`
	SyncedAt *string         `json:"syncedAt"`
	// Highlights are today's Health readings, each omitted when the member has none.
	Highlights highlightsJSON `json:"highlights"`
}

type highlightsJSON struct {
	Steps           *float64 `json:"steps,omitempty"`
	ExerciseMinutes *float64 `json:"exercise_minutes,omitempty"`
	SleepMinutes    *float64 `json:"sleep_minutes,omitempty"`
}

// seasonOn is the season a local date belongs to. Before the first season starts, which a user
// behind UTC sees on the night of the first deploy, the board shows the upcoming one with no
// points yet.
func seasonOn(date score.Date, seasons []score.Season) (score.Season, bool) {
	if season, ok := score.SeasonFor(date, seasons); ok {
		return season, true
	}
	for _, season := range seasons {
		if season.StartsOn.After(date) {
			return season, true
		}
	}
	return score.Season{}, false
}

// handleBoard compares everyone on the server. Each person is measured on their own local
// today, week and season, and the caller comes first.
func (s *Server) handleBoard(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	seasons, err := db.ListSeasons(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	header, ok := seasonOn(score.LocalToday(s.now(), c.loc), seasons)
	if !ok {
		fail(w, r, newErr(http.StatusInternalServerError, codeInternal, "no season is configured"))
		return
	}
	users, err := db.ListUsers(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	slices.SortStableFunc(users, func(a, b db.User) int {
		switch {
		case a.ID == c.user.ID:
			return -1
		case b.ID == c.user.ID:
			return 1
		}
		return 0
	})

	entries := make([]boardUserJSON, 0, len(users))
	for _, u := range users {
		entry, err := s.boardEntry(ctx, u, seasons)
		if err != nil {
			fail(w, r, err)
			return
		}
		entries = append(entries, entry)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"season":    seasonJSON{Name: header.Name, StartsOn: header.StartsOn, EndsOn: header.EndsOn},
		"serverNow": wireTime(s.now()),
		"users":     entries,
	})
}

func (s *Server) boardEntry(ctx context.Context, u db.User, seasons []score.Season) (boardUserJSON, error) {
	loc, err := u.Location()
	if err != nil {
		return boardUserJSON{}, err
	}
	now := s.now()
	today := score.LocalToday(now, loc)
	season, _ := seasonOn(today, seasons)

	streak, err := engine.StreakFor(ctx, s.db.Pool, u, now, loc)
	if err != nil {
		return boardUserJSON{}, err
	}
	recent, err := db.ListDayScores(ctx, s.db.Pool, u.ID, today.AddDays(-6), today)
	if err != nil {
		return boardUserJSON{}, err
	}
	byDate := make(map[score.Date]db.DayScoreRow, len(recent))
	for _, row := range recent {
		byDate[row.LocalDate] = row
	}
	last7 := make([]dayMarkJSON, 0, 7)
	for d := today.AddDays(-6); !d.After(today); d = d.AddDays(1) {
		row := byDate[d]
		last7 = append(last7, dayMarkJSON{Date: d, Percent: row.Percent, Counted: row.Counted, Rest: slices.Contains(streak.RestDays, d)})
	}

	weekFrom, _ := season.WeekRange(today)
	week, err := db.SumPoints(ctx, s.db.Pool, u.ID, weekFrom, today)
	if err != nil {
		return boardUserJSON{}, err
	}
	total, err := db.SumPoints(ctx, s.db.Pool, u.ID, season.StartsOn, today)
	if err != nil {
		return boardUserJSON{}, err
	}
	syncedAt, err := db.LastHealthSync(ctx, s.db.Pool, u.ID)
	if err != nil {
		return boardUserJSON{}, err
	}
	readings, err := db.HealthDay(ctx, s.db.Pool, u.ID, today)
	if err != nil {
		return boardUserJSON{}, err
	}
	pick := func(key string) *float64 {
		if v, ok := readings[key]; ok {
			return &v
		}
		return nil
	}
	todayRow := byDate[today]
	return boardUserJSON{
		ID: u.ID, Name: u.Name, Color: u.Color,
		Today:    boardDayJSON{Points: todayRow.Points(), Percent: todayRow.Percent, Counted: todayRow.Counted},
		Week:     pointsJSON{Points: week},
		Season:   pointsJSON{Points: total},
		Streak:   streakCountJSON{Current: streak.Count},
		Last7:    last7,
		SyncedAt: wireTimePtr(syncedAt),
		Highlights: highlightsJSON{
			Steps: pick(db.MetricSteps), ExerciseMinutes: pick(db.MetricExercise), SleepMinutes: pick(db.MetricSleep),
		},
	}, nil
}

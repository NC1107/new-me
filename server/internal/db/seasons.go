package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// ListSeasons returns every season, earliest first.
func ListSeasons(ctx context.Context, q Querier) ([]score.Season, error) {
	rows, err := q.Query(ctx,
		`SELECT id, name, starts_on::text, ends_on::text FROM seasons ORDER BY starts_on`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []score.Season
	for rows.Next() {
		var s score.Season
		if err := rows.Scan(&s.ID, &s.Name, &s.StartsOn, &s.EndsOn); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

package db

import (
	"context"
	"fmt"
)

const tidyFoodNamesFix = "datafix_tidy_food_names"

// TidyFoodNames rewrites the name and brand of saved database foods with tidy, once. It never
// touches foods a person typed or estimated, and a marker row keeps later edits of a database
// food from being tidied again on the next boot. It returns how many foods changed.
func (d *DB) TidyFoodNames(ctx context.Context, tidy func(name, brand string) (string, string)) (int, error) {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("begin tidy food names: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx,
		`INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, tidyFoodNamesFix)
	if err != nil {
		return 0, fmt.Errorf("mark tidy food names: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return 0, nil
	}

	rows, err := tx.Query(ctx,
		`SELECT id, name, brand FROM foods WHERE source IN ('usda', 'openfoodfacts') FOR UPDATE`)
	if err != nil {
		return 0, fmt.Errorf("list database foods: %w", err)
	}
	type change struct {
		id          int64
		name, brand string
	}
	var changes []change
	for rows.Next() {
		var id int64
		var name, brand string
		if err := rows.Scan(&id, &name, &brand); err != nil {
			rows.Close()
			return 0, err
		}
		if newName, newBrand := tidy(name, brand); newName != name || newBrand != brand {
			changes = append(changes, change{id, newName, newBrand})
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for _, c := range changes {
		if _, err := tx.Exec(ctx,
			`UPDATE foods SET name = $2, brand = $3, updated_at = now() WHERE id = $1`, c.id, c.name, c.brand); err != nil {
			return 0, fmt.Errorf("tidy food %d: %w", c.id, err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("commit tidy food names: %w", err)
	}
	return len(changes), nil
}

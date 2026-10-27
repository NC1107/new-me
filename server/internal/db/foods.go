package db

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// FoodServing is an alternate serving of a library food: a label and its weight.
type FoodServing struct {
	Text  string  `json:"text"`
	Grams float64 `json:"grams"`
}

// Food is one saved food. Nutrients are per ServingText.
type Food struct {
	ID           int64
	Name         string
	Brand        string
	ServingText  string
	ServingGrams float64
	Kcal         int
	Protein      float64
	Carbs        float64
	Fat          float64
	Fiber        float64
	Source       string
	SourceID     string
	Servings     []FoodServing
	CreatedBy    *int64
	UseCount     int
	LastUsedAt   *time.Time
}

const foodColumns = `id, name, brand, serving_text, serving_grams::float8, kcal, protein_g::float8, carbs_g::float8,
	fat_g::float8, fiber_g::float8, source, source_id, alt_servings, created_by, use_count, last_used_at`

func scanFood(row pgx.Row) (Food, error) {
	var f Food
	var alts []byte
	err := row.Scan(&f.ID, &f.Name, &f.Brand, &f.ServingText, &f.ServingGrams, &f.Kcal, &f.Protein, &f.Carbs,
		&f.Fat, &f.Fiber, &f.Source, &f.SourceID, &alts, &f.CreatedBy, &f.UseCount, &f.LastUsedAt)
	if err != nil {
		return f, err
	}
	if err := json.Unmarshal(alts, &f.Servings); err != nil {
		return f, err
	}
	if f.Servings == nil {
		f.Servings = []FoodServing{}
	}
	return f, nil
}

// ListFoods returns the library, most used first.
func ListFoods(ctx context.Context, q Querier) ([]Food, error) {
	rows, err := q.Query(ctx, `SELECT `+foodColumns+` FROM foods ORDER BY use_count DESC, last_used_at DESC NULLS LAST, name LIMIT 2000`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Food{}
	for rows.Next() {
		f, err := scanFood(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

// GetFood returns one food or ErrNotFound.
func GetFood(ctx context.Context, q Querier, id int64) (Food, error) {
	f, err := scanFood(q.QueryRow(ctx, `SELECT `+foodColumns+` FROM foods WHERE id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return f, ErrNotFound
	}
	return f, err
}

// FoodBySource returns the saved copy of a database food, or ErrNotFound.
func FoodBySource(ctx context.Context, q Querier, source, sourceID string) (Food, error) {
	f, err := scanFood(q.QueryRow(ctx, `SELECT `+foodColumns+` FROM foods WHERE source = $1 AND source_id = $2`, source, sourceID))
	if errors.Is(err, pgx.ErrNoRows) {
		return f, ErrNotFound
	}
	return f, err
}

// InsertFood saves a food and returns it with its id.
func InsertFood(ctx context.Context, q Querier, f Food, createdBy int64) (Food, error) {
	alts, err := json.Marshal(f.Servings)
	if err != nil {
		return f, err
	}
	return scanFood(q.QueryRow(ctx, `INSERT INTO foods (name, brand, serving_text, serving_grams, kcal, protein_g, carbs_g,
		fat_g, fiber_g, source, source_id, alt_servings, created_by)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING `+foodColumns,
		f.Name, f.Brand, f.ServingText, f.ServingGrams, f.Kcal, f.Protein, f.Carbs, f.Fat, f.Fiber, f.Source, f.SourceID,
		alts, createdBy))
}

// UpdateFood replaces the editable fields of a food.
func UpdateFood(ctx context.Context, q Querier, f Food) (Food, error) {
	alts, err := json.Marshal(f.Servings)
	if err != nil {
		return f, err
	}
	out, err := scanFood(q.QueryRow(ctx, `UPDATE foods SET name=$2, brand=$3, serving_text=$4, serving_grams=$5, kcal=$6,
		protein_g=$7, carbs_g=$8, fat_g=$9, fiber_g=$10, alt_servings=$11, updated_at=now() WHERE id=$1 RETURNING `+foodColumns,
		f.ID, f.Name, f.Brand, f.ServingText, f.ServingGrams, f.Kcal, f.Protein, f.Carbs, f.Fat, f.Fiber, alts))
	if errors.Is(err, pgx.ErrNoRows) {
		return out, ErrNotFound
	}
	return out, err
}

// DeleteFood removes a food from the library.
func DeleteFood(ctx context.Context, q Querier, id int64) error {
	tag, err := q.Exec(ctx, `DELETE FROM foods WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// UseFood records one use of a food.
func UseFood(ctx context.Context, q Querier, id int64, at time.Time) (Food, error) {
	f, err := scanFood(q.QueryRow(ctx, `UPDATE foods SET use_count = use_count + 1, last_used_at = $2 WHERE id = $1 RETURNING `+foodColumns, id, at))
	if errors.Is(err, pgx.ErrNoRows) {
		return f, ErrNotFound
	}
	return f, err
}

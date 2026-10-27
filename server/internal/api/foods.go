package api

import (
	"context"
	"errors"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/estimate"
)

// Library limits mirror the table checks, enforced first so the caller gets a 422 naming the field.
const (
	maxFoodName     = 80
	maxFoodBrand    = 40
	maxServingText  = 60
	maxServingLabel = 40
	maxServings     = 8
	maxFoodGrams    = 5000
	maxFoodSourceID = 40
	maxSearchLimit  = 50
	maxRemote       = 10
)

var errNoFood = newErr(http.StatusNotFound, codeNotFound, "no such food")

type servingJSON struct {
	Text  string  `json:"text"`
	Grams float64 `json:"grams"`
}

// libFoodJSON is a saved food, or an unsaved candidate from a database (id null, saved false).
type libFoodJSON struct {
	ID           *int64        `json:"id"`
	Saved        bool          `json:"saved"`
	Name         string        `json:"name"`
	Brand        string        `json:"brand"`
	ServingText  string        `json:"servingText"`
	ServingGrams float64       `json:"servingGrams"`
	Kcal         int           `json:"kcal"`
	Protein      float64       `json:"protein"`
	Carbs        float64       `json:"carbs"`
	Fat          float64       `json:"fat"`
	Fiber        float64       `json:"fiber"`
	Source       string        `json:"source"`
	SourceID     string        `json:"sourceId"`
	Servings     []servingJSON `json:"servings"`
	UseCount     int           `json:"useCount"`
	LastUsedAt   *time.Time    `json:"lastUsedAt"`
}

func toLibFoodJSON(f db.Food) libFoodJSON {
	servings := make([]servingJSON, len(f.Servings))
	for i, s := range f.Servings {
		servings[i] = servingJSON{Text: s.Text, Grams: s.Grams}
	}
	id := f.ID
	return libFoodJSON{ID: &id, Saved: true, Name: f.Name, Brand: f.Brand, ServingText: f.ServingText,
		ServingGrams: f.ServingGrams, Kcal: f.Kcal, Protein: f.Protein, Carbs: f.Carbs, Fat: f.Fat,
		Fiber: f.Fiber, Source: f.Source, SourceID: f.SourceID, Servings: servings, UseCount: f.UseCount,
		LastUsedAt: f.LastUsedAt}
}

func roundTenth(v float64) float64 { return math.Round(v*10) / 10 }

// candidateJSON offers a database food as an unsaved library entry.
func candidateJSON(f estimate.Food) (libFoodJSON, bool) {
	v := f.Serving()
	if v.Text == "" {
		return libFoodJSON{}, false
	}
	servings := []servingJSON{}
	for _, a := range v.Alts {
		if a.Grams > 0 && a.Label != "" && len(servings) < maxServings {
			servings = append(servings, servingJSON{Text: "1 " + a.Label, Grams: roundTenth(a.Grams)})
		}
	}
	name := f.Name
	if utf8.RuneCountInString(name) > maxFoodName {
		name = string([]rune(name)[:maxFoodName])
	}
	return libFoodJSON{Name: name, Brand: truncate(f.Brand, maxFoodBrand), ServingText: truncate(v.Text, maxServingText),
		ServingGrams: roundTenth(v.Grams), Kcal: int(math.Round(v.N.Kcal)), Protein: roundTenth(v.N.Protein),
		Carbs: roundTenth(v.N.Carbs), Fat: roundTenth(v.N.Fat), Fiber: roundTenth(v.N.Fiber),
		Source: f.Source, SourceID: f.ID, Servings: servings}, true
}

func truncate(s string, n int) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) > n {
		return strings.TrimSpace(string([]rune(s)[:n]))
	}
	return s
}

// libraryStore lets the estimate pipeline read the saved foods.
type libraryStore struct{ db *db.DB }

func (l libraryStore) All(ctx context.Context) ([]estimate.LibraryFood, error) {
	foods, err := db.ListFoods(ctx, l.db.Pool)
	if err != nil {
		return nil, err
	}
	return toLibrary(foods), nil
}

func toLibrary(foods []db.Food) []estimate.LibraryFood {
	out := make([]estimate.LibraryFood, len(foods))
	for i, f := range foods {
		lf := estimate.LibraryFood{ID: f.ID, Name: f.Name, Brand: f.Brand, ServingText: f.ServingText,
			ServingGrams: f.ServingGrams, Source: f.Source, SourceID: f.SourceID, UseCount: f.UseCount,
			N: estimate.Nutrients{Kcal: float64(f.Kcal), Protein: f.Protein, Carbs: f.Carbs, Fat: f.Fat, Fiber: f.Fiber}}
		for _, s := range f.Servings {
			lf.Servings = append(lf.Servings, estimate.Portion{Label: s.Text, Grams: s.Grams})
		}
		out[i] = lf
	}
	return out
}

// handleListFoods searches the library, most used first. With remote=1 it also returns
// unsaved candidates from USDA and Open Food Facts; the app asks for those only on request,
// since the shared USDA demo key allows few calls an hour.
func (s *Server) handleListFoods(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if utf8.RuneCountInString(q) > maxFoodName || hasControlChars(q) {
		fail(w, r, invalid("q must be at most 80 characters without control characters"))
		return
	}
	foods, err := db.ListFoods(r.Context(), s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	ranked := estimate.SearchLibrary(q, toLibrary(foods))
	byID := make(map[int64]db.Food, len(foods))
	saved := map[string]bool{}
	for _, f := range foods {
		byID[f.ID] = f
		if f.SourceID != "" {
			saved[f.Source+"|"+f.SourceID] = true
		}
	}
	out := struct {
		Foods      []libFoodJSON `json:"foods"`
		Candidates []libFoodJSON `json:"candidates"`
	}{Foods: []libFoodJSON{}, Candidates: []libFoodJSON{}}
	for _, l := range ranked {
		if len(out.Foods) == maxSearchLimit {
			break
		}
		out.Foods = append(out.Foods, toLibFoodJSON(byID[l.ID]))
	}
	if r.URL.Query().Get("remote") == "1" && q != "" && s.foods != nil {
		for _, f := range s.foods.SearchRemote(r.Context(), q) {
			c, ok := candidateJSON(f)
			if !ok || saved[c.Source+"|"+c.SourceID] || len(out.Candidates) == maxRemote {
				continue
			}
			out.Candidates = append(out.Candidates, c)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

type foodRequest struct {
	Name         *string        `json:"name"`
	Brand        *string        `json:"brand"`
	ServingText  *string        `json:"servingText"`
	ServingGrams *float64       `json:"servingGrams"`
	Kcal         *float64       `json:"kcal"`
	Protein      *float64       `json:"protein"`
	Carbs        *float64       `json:"carbs"`
	Fat          *float64       `json:"fat"`
	Fiber        *float64       `json:"fiber"`
	Source       *string        `json:"source"`
	SourceID     *string        `json:"sourceId"`
	Servings     *[]servingJSON `json:"servings"`
}

// apply validates the request fields that are set and writes them into f.
func (req foodRequest) apply(f *db.Food) *httpError {
	text := func(p *string, field string, min, max int, dst *string) *httpError {
		if p == nil {
			return nil
		}
		v := strings.TrimSpace(*p)
		if n := utf8.RuneCountInString(v); n < min || n > max || hasControlChars(v) {
			return invalid(field + " must be " + strconv.Itoa(min) + " to " + strconv.Itoa(max) + " characters without control characters")
		}
		*dst = v
		return nil
	}
	num := func(p *float64, field string, max float64, dst *float64) *httpError {
		if p == nil {
			return nil
		}
		if math.IsNaN(*p) || math.IsInf(*p, 0) || *p < 0 || *p > max {
			return invalid(field + " must be between 0 and " + strconv.FormatFloat(max, 'f', -1, 64))
		}
		*dst = roundTenth(*p)
		return nil
	}
	for _, err := range []*httpError{
		text(req.Name, "name", 1, maxFoodName, &f.Name),
		text(req.Brand, "brand", 0, maxFoodBrand, &f.Brand),
		text(req.ServingText, "servingText", 1, maxServingText, &f.ServingText),
		num(req.ServingGrams, "servingGrams", maxFoodGrams, &f.ServingGrams),
		num(req.Protein, "protein", estimate.MaxMacroGrams, &f.Protein),
		num(req.Carbs, "carbs", estimate.MaxMacroGrams, &f.Carbs),
		num(req.Fat, "fat", estimate.MaxMacroGrams, &f.Fat),
		num(req.Fiber, "fiber", estimate.MaxMacroGrams, &f.Fiber),
	} {
		if err != nil {
			return err
		}
	}
	if req.Kcal != nil {
		if math.IsNaN(*req.Kcal) || *req.Kcal < 0 || *req.Kcal > estimate.MaxKcal {
			return invalid("kcal must be between 0 and 10000")
		}
		f.Kcal = int(math.Round(*req.Kcal))
	}
	if req.Servings != nil {
		if len(*req.Servings) > maxServings {
			return invalid("at most 8 alternate servings")
		}
		servings := make([]db.FoodServing, 0, len(*req.Servings))
		for _, sv := range *req.Servings {
			t := strings.TrimSpace(sv.Text)
			if n := utf8.RuneCountInString(t); n < 1 || n > maxServingLabel || hasControlChars(t) ||
				math.IsNaN(sv.Grams) || sv.Grams <= 0 || sv.Grams > maxFoodGrams {
				return invalid("each serving needs a label of at most 40 characters and grams between 0 and 5000")
			}
			servings = append(servings, db.FoodServing{Text: t, Grams: roundTenth(sv.Grams)})
		}
		f.Servings = servings
	}
	return nil
}

// handleCreateFood saves a candidate or a manual food. A database food that is already saved
// answers 200 with the saved copy, so saving on log is safe to repeat.
func (s *Server) handleCreateFood(w http.ResponseWriter, r *http.Request) {
	var req foodRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Name == nil || req.ServingText == nil || req.Kcal == nil {
		fail(w, r, invalid("name, servingText and kcal are required"))
		return
	}
	f := db.Food{Source: "manual", Servings: []db.FoodServing{}}
	if req.Source != nil {
		f.Source = *req.Source
	}
	switch f.Source {
	case "usda", "openfoodfacts", "manual", "estimated":
	default:
		fail(w, r, invalid("source must be usda, openfoodfacts, manual or estimated"))
		return
	}
	if req.SourceID != nil {
		f.SourceID = strings.TrimSpace(*req.SourceID)
		if utf8.RuneCountInString(f.SourceID) > maxFoodSourceID || hasControlChars(f.SourceID) {
			fail(w, r, invalid("sourceId must be at most 40 characters"))
			return
		}
	}
	if err := req.apply(&f); err != nil {
		fail(w, r, err)
		return
	}
	ctx := r.Context()
	if f.SourceID != "" {
		if existing, err := db.FoodBySource(ctx, s.db.Pool, f.Source, f.SourceID); err == nil {
			writeJSON(w, http.StatusOK, toLibFoodJSON(existing))
			return
		} else if !errors.Is(err, db.ErrNotFound) {
			fail(w, r, err)
			return
		}
	}
	created, err := db.InsertFood(ctx, s.db.Pool, f, callerFrom(r).user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, toLibFoodJSON(created))
}

func foodID(r *http.Request) (int64, *httpError) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		return 0, errNoFood
	}
	return id, nil
}

// handlePatchFood edits a saved food. Anyone in the household may edit it: the library is shared.
func (s *Server) handlePatchFood(w http.ResponseWriter, r *http.Request) {
	id, herr := foodID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	var req foodRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Source != nil || req.SourceID != nil {
		fail(w, r, invalid("source and sourceId cannot be changed"))
		return
	}
	f, err := db.GetFood(r.Context(), s.db.Pool, id)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoFood)
		return
	} else if err != nil {
		fail(w, r, err)
		return
	}
	if herr := req.apply(&f); herr != nil {
		fail(w, r, herr)
		return
	}
	updated, err := db.UpdateFood(r.Context(), s.db.Pool, f)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoFood)
		return
	} else if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, toLibFoodJSON(updated))
}

func (s *Server) handleDeleteFood(w http.ResponseWriter, r *http.Request) {
	id, herr := foodID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	if err := db.DeleteFood(r.Context(), s.db.Pool, id); errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoFood)
		return
	} else if err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleUseFood records that a meal using the food was logged, which ranks it higher next time.
func (s *Server) handleUseFood(w http.ResponseWriter, r *http.Request) {
	id, herr := foodID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	f, err := db.UseFood(r.Context(), s.db.Pool, id, s.now())
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoFood)
		return
	} else if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, toLibFoodJSON(f))
}

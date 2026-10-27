// Package estimate turns a photo or a sentence about a meal into the numbers of a meal log
// entry. A sentence is split into items by Claude and each item is looked up in a real food
// database; Claude only estimates what no database knows, and a photo is a pure Claude
// estimate. Everything is validated and clamped here to the bounds the meal log enforces, so a
// wild answer can never reach the form unchecked.
package estimate

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/nc1107/new-me/server/internal/anthropic"
)

// Bounds mirror what POST /api/logs accepts for a meal.
const (
	MaxNameRunes  = 80
	MaxKcal       = 10000
	MaxMacroGrams = 5000
	MaxNoteRunes  = 200
	// MaxImageBytes is the largest decoded photo accepted.
	MaxImageBytes = 5 << 20
	MaxTextRunes  = 500
)

// Confidence levels the model may report.
const (
	ConfidenceLow    = "low"
	ConfidenceMedium = "medium"
	ConfidenceHigh   = "high"
)

// Estimate is one meal's nutrition, already inside the meal log bounds.
type Estimate struct {
	Name       string  `json:"name"`
	Kcal       int     `json:"kcal"`
	Protein    float64 `json:"protein"`
	Carbs      float64 `json:"carbs"`
	Fat        float64 `json:"fat"`
	Fiber      float64 `json:"fiber"`
	Confidence string  `json:"confidence"`
	Notes      string  `json:"notes"`
}

var (
	// ErrBadImage means the upload is not a JPEG or PNG of an accepted size.
	ErrBadImage = errors.New("image must be a base64 JPEG or PNG")
	// ErrImageTooLarge means the decoded image is over MaxImageBytes.
	ErrImageTooLarge = errors.New("image is larger than 5 MB")
	// ErrUnusable means the model answered, but not with a usable estimate.
	ErrUnusable = errors.New("estimate: unusable answer")
)

const systemPrompt = `You estimate the nutrition of one meal for a personal food log.
Answer only by calling the tool. Estimate the whole portion shown or described, not per 100 g.
Use realistic restaurant or home portion sizes. If the portion is unclear, assume a typical single serving and say so in notes.
name is a short plain-language title of the meal. kcal is a whole number. protein, carbs, fat and fiber are grams.
confidence is high only when the food and its portion are both clear, medium when one is a guess, low when both are.
notes is one short sentence on the main assumption. Never refuse: give your best estimate.`

func schema() map[string]any {
	number := func(desc string) map[string]any { return map[string]any{"type": "number", "description": desc} }
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"name":       map[string]any{"type": "string", "description": "Short title of the meal, at most 80 characters"},
			"kcal":       number("Total energy in kilocalories"),
			"protein":    number("Protein in grams"),
			"carbs":      number("Carbohydrate in grams"),
			"fat":        number("Fat in grams"),
			"fiber":      number("Fiber in grams"),
			"confidence": map[string]any{"type": "string", "enum": []string{ConfidenceLow, ConfidenceMedium, ConfidenceHigh}},
			"notes":      map[string]any{"type": "string", "description": "One short sentence on the main assumption"},
		},
		"required":             []string{"name", "kcal", "protein", "carbs", "fat", "fiber", "confidence", "notes"},
		"additionalProperties": false,
	}
}

// ValidateImage checks the media type, the base64 and the size, and sniffs the magic bytes so
// the declared type matches the content. It returns the normalized base64 payload.
func ValidateImage(mediaType, b64 string) (string, error) {
	b64 = strings.TrimSpace(b64)
	// Decoding bounds the memory: base64 is 4/3 of the data, so anything far larger is refused first.
	if len(b64) > base64.StdEncoding.EncodedLen(MaxImageBytes)+8 {
		return "", ErrImageTooLarge
	}
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(raw) == 0 {
		return "", ErrBadImage
	}
	if len(raw) > MaxImageBytes {
		return "", ErrImageTooLarge
	}
	switch mediaType {
	case "image/jpeg":
		if len(raw) < 3 || raw[0] != 0xFF || raw[1] != 0xD8 || raw[2] != 0xFF {
			return "", ErrBadImage
		}
	case "image/png":
		if len(raw) < 8 || string(raw[:8]) != "\x89PNG\r\n\x1a\x0a" {
			return "", ErrBadImage
		}
	default:
		return "", ErrBadImage
	}
	return b64, nil
}

// Parse validates and clamps the tool arguments. A missing or non-numeric kcal makes the
// answer unusable; the other numbers default to zero and the confidence to low.
func Parse(raw json.RawMessage) (Estimate, error) {
	var in struct {
		Name       string   `json:"name"`
		Kcal       *float64 `json:"kcal"`
		Protein    *float64 `json:"protein"`
		Carbs      *float64 `json:"carbs"`
		Fat        *float64 `json:"fat"`
		Fiber      *float64 `json:"fiber"`
		Confidence string   `json:"confidence"`
		Notes      string   `json:"notes"`
	}
	if err := json.Unmarshal(raw, &in); err != nil {
		return Estimate{}, fmt.Errorf("%w: %v", ErrUnusable, err)
	}
	if in.Kcal == nil || math.IsNaN(*in.Kcal) || math.IsInf(*in.Kcal, 0) {
		return Estimate{}, fmt.Errorf("%w: no kcal", ErrUnusable)
	}
	out := Estimate{
		Name:       cleanText(in.Name, MaxNameRunes),
		Kcal:       int(math.Min(math.Max(math.Round(*in.Kcal), 1), MaxKcal)),
		Protein:    grams(in.Protein),
		Carbs:      grams(in.Carbs),
		Fat:        grams(in.Fat),
		Fiber:      grams(in.Fiber),
		Confidence: strings.ToLower(strings.TrimSpace(in.Confidence)),
		Notes:      cleanText(in.Notes, MaxNoteRunes),
	}
	if out.Name == "" {
		out.Name = "Meal"
	}
	switch out.Confidence {
	case ConfidenceLow, ConfidenceMedium, ConfidenceHigh:
	default:
		out.Confidence = ConfidenceLow
	}
	return out, nil
}

func grams(v *float64) float64 {
	if v == nil || math.IsNaN(*v) || math.IsInf(*v, 0) {
		return 0
	}
	return math.Round(math.Min(math.Max(*v, 0), MaxMacroGrams)*10) / 10
}

// cleanText drops control characters, collapses whitespace and cuts to a rune budget.
func cleanText(s string, maxRunes int) string {
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, s)
	s = strings.Join(strings.Fields(s), " ")
	if utf8.RuneCountInString(s) > maxRunes {
		s = strings.TrimSpace(string([]rune(s)[:maxRunes]))
	}
	return s
}

// Estimator asks Claude for estimates. Typed text goes through the itemized pipeline in
// meal.go; photos stay a single Claude estimate.
type Estimator struct {
	Client *anthropic.Client
	// Foods is nil in tests that only need the Claude steps; every item is then estimated.
	Foods *Foods
	// Library is the household's saved foods, checked before any database; nil skips it.
	Library Library
}

func (e *Estimator) run(ctx context.Context, system string, user []anthropic.Block) (Estimate, error) {
	raw, err := e.Client.ToolInput(ctx, anthropic.Request{
		System: system, User: user, MaxTokens: 600,
		Tool: &anthropic.Tool{
			Name: "report_meal_estimate", Description: "Report the estimated nutrition of the meal.", Schema: schema()},
	})
	if err != nil {
		return Estimate{}, err
	}
	return Parse(raw)
}

// FromImage estimates the meal in a photo; the optional hint is the person's own words about it.
// The image is only forwarded, never stored.
func (e *Estimator) FromImage(ctx context.Context, mediaType, b64, hint string) (Estimate, error) {
	blocks := []anthropic.Block{{MediaType: mediaType, ImageB64: b64}}
	text := "Estimate the meal in this photo."
	if hint != "" {
		text += " The person says: " + hint
	}
	return e.run(ctx, systemPrompt, append(blocks, anthropic.Block{Text: text}))
}

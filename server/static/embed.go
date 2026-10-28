// Package static embeds the exercise photos so the server serves them without a third-party host.
package static

import "embed"

// Exercises holds the how-to photos as exercises/<key>-<n>.jpg.
//
//go:embed exercises/*.jpg
var Exercises embed.FS

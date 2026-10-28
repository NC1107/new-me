#!/usr/bin/env bash
# Rebuilds server/static/exercises/<key>-<n>.jpg from free-exercise-db (Unlicense) using SOURCES.tsv.
# Needs curl and ImageMagick. Images are scaled to 480 px wide and compressed under 60 KB.
set -euo pipefail
cd "$(dirname "$0")/../static/exercises"
base=https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises
grep -v '^#' SOURCES.tsv | awk -F'\t' '$2 != "" {print $1 "\t" $2}' | while IFS=$'\t' read -r key src; do
  [ -n "$src" ] || continue
  for n in 0 1; do
    tmp=$(mktemp)
    curl -fsSL "$base/$src/$n.jpg" -o "$tmp"
    q=80
    magick "$tmp" -resize 480x -strip -interlace JPEG -quality $q "$key-$n.jpg"
    while [ "$(stat -c %s "$key-$n.jpg")" -gt 60000 ] && [ $q -gt 40 ]; do
      q=$((q - 8))
      magick "$tmp" -resize 480x -strip -interlace JPEG -quality $q "$key-$n.jpg"
    done
    rm -f "$tmp"
  done
  # Some source entries repeat one photo; keep a single file so the app shows one image.
  if cmp -s "$key-0.jpg" "$key-1.jpg"; then rm -f "$key-1.jpg"; fi
done

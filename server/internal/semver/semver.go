// Package semver compares the dotted app versions the client reports.
package semver

import (
	"fmt"
	"strconv"
	"strings"
)

// Version is major, minor and patch.
type Version [3]int

// Parse reads "x.y.z", tolerating a leading "v", a missing minor or patch, and any "+build" or
// "-prerelease" suffix, which never affects ordering here.
func Parse(s string) (Version, error) {
	core := strings.TrimPrefix(strings.TrimSpace(s), "v")
	if i := strings.IndexAny(core, "+-"); i >= 0 {
		core = core[:i]
	}
	parts := strings.Split(core, ".")
	if core == "" || len(parts) > 3 {
		return Version{}, fmt.Errorf("invalid version %q", s)
	}
	var v Version
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return Version{}, fmt.Errorf("invalid version %q", s)
		}
		v[i] = n
	}
	return v, nil
}

// Less reports whether v is an older version than other.
func (v Version) Less(other Version) bool {
	for i := range v {
		if v[i] != other[i] {
			return v[i] < other[i]
		}
	}
	return false
}

package estimate

import (
	"sync"
	"time"

	"golang.org/x/sync/singleflight"
)

const (
	cacheTTL = time.Hour
	// cacheMax bounds memory; when full the oldest entries are dropped wholesale, which is fine
	// for a two-person server.
	cacheMax = 512
)

type cacheEntry struct {
	val     any
	expires time.Time
}

// ttlCache keeps successful lookups for an hour so a repeated meal costs no API calls.
type ttlCache struct {
	mu     sync.Mutex
	now    func() time.Time
	m      map[string]cacheEntry
	flight singleflight.Group
}

func newTTLCache(now func() time.Time) *ttlCache {
	return &ttlCache{now: now, m: map[string]cacheEntry{}}
}

func (c *ttlCache) get(key string) (any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.m[key]
	if !ok || !c.now().Before(e.expires) {
		delete(c.m, key)
		return nil, false
	}
	return e.val, true
}

func (c *ttlCache) set(key string, val any) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.m) >= cacheMax {
		now := c.now()
		for k, e := range c.m {
			if !now.Before(e.expires) {
				delete(c.m, k)
			}
		}
		if len(c.m) >= cacheMax {
			c.m = map[string]cacheEntry{}
		}
	}
	c.m[key] = cacheEntry{val: val, expires: c.now().Add(cacheTTL)}
}

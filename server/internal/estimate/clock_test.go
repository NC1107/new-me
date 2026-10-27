package estimate

import (
	"sync"
	"time"
)

type fakeNow struct {
	mu sync.Mutex
	t  time.Time
}

func timeNow() *fakeNow { return &fakeNow{t: time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)} }

func (f *fakeNow) get() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.t
}

func (f *fakeNow) advance(seconds int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.t = f.t.Add(time.Duration(seconds) * time.Second)
}

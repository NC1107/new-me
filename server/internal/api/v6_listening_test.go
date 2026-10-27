package api

import (
	"net/http"
	"testing"
	"time"
)

func TestManualSyncIsOffWithoutAURLAndNeedsALink(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/me/audiobookshelf/sync", nick.Token, nil).expect(http.StatusNotFound).code("abs_disabled")

	opt, _ := withABS(t)
	h2 := newHarness(t, opt)
	nadia := h2.joinAdmin("Nadia", "violet")
	h2.post("/api/me/audiobookshelf/sync", nadia.Token, nil).expect(http.StatusNotFound).code("abs_not_linked")
	h2.post("/api/me/audiobookshelf/sync", "", nil).expect(http.StatusUnauthorized)
}

func TestManualSyncReadsNowAndThrottlesToOncePerMinute(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	fake.SetListening("nick", "2026-11-02", 5*60)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).expect(http.StatusOK)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.num("listening.minutes") != 5 || today.str("listening.syncedAt") != "2026-11-02T17:00:00Z" {
		t.Fatalf("today listening = %s", today.Body)
	}

	// Another 20 minutes are listened to; the first sync after the link is within a minute of it.
	fake.SetListening("nick", "2026-11-02", 25*60)
	h.clock.Set(h.clock.Now().Add(2 * time.Minute))
	_, _, before := fake.Counts()
	first := h.post("/api/me/audiobookshelf/sync", nick.Token, nil).expect(http.StatusOK)
	_, _, afterFirst := fake.Counts()
	if !first.flag("linked") || first.str("username") != "nick" || first.num("minutesToday") != 25 ||
		first.str("syncedAt") != "2026-11-02T17:02:00Z" || !first.isNull("lastError") || afterFirst == before {
		t.Fatalf("first sync = %s (stats %d -> %d)", first.Body, before, afterFirst)
	}

	fake.SetListening("nick", "2026-11-02", 40*60)
	h.clock.Set(h.clock.Now().Add(59 * time.Second))
	throttled := h.post("/api/me/audiobookshelf/sync", nick.Token, nil).expect(http.StatusOK)
	_, _, afterThrottled := fake.Counts()
	if throttled.num("minutesToday") != 25 || afterThrottled != afterFirst {
		t.Fatalf("throttled sync = %s (stats %d -> %d), want the last state without calling out", throttled.Body, afterFirst, afterThrottled)
	}

	h.clock.Set(h.clock.Now().Add(2 * time.Second))
	fresh := h.post("/api/me/audiobookshelf/sync", nick.Token, nil).expect(http.StatusOK)
	if fresh.num("minutesToday") != 40 {
		t.Fatalf("after the throttle = %s", fresh.Body)
	}
}

func TestManualSyncThrottleIsPerPerson(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	fake.AddUser("nadia", "pw")
	nick, nadia := h.pair()
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).expect(http.StatusOK)
	h.put("/api/me/audiobookshelf", nadia.Token, obj{"username": "nadia", "password": "pw"}).expect(http.StatusOK)

	h.post("/api/me/audiobookshelf/sync", nick.Token, nil).expect(http.StatusOK)
	_, _, a := fake.Counts()
	h.post("/api/me/audiobookshelf/sync", nadia.Token, nil).expect(http.StatusOK)
	_, _, b := fake.Counts()
	if b == a {
		t.Fatal("Nadia's sync must not be throttled by Nick's")
	}
}

func TestManualSyncReportsAnUnreachableServerAsLastError(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).expect(http.StatusOK)

	fake.SetDown(true)
	got := h.post("/api/me/audiobookshelf/sync", nick.Token, nil).expect(http.StatusOK)
	if !got.flag("linked") || got.str("lastError") != "unreachable" || got.str("syncedAt") != "2026-11-02T17:00:00Z" {
		t.Fatalf("sync while down = %s", got.Body)
	}
}

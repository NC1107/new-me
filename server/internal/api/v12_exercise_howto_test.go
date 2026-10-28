package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
)

const maxImageBytes = 60 * 1000

func TestEveryCatalogExerciseHasAHowTo(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	withPhotos := 0
	for i := 0; i < got.length("exercises"); i++ {
		p := fmt.Sprintf("exercises.%d.", i)
		key := got.str(p + "key")
		if steps := got.length(p + "steps"); steps < 3 || steps > 6 {
			t.Errorf("%s has %d steps, want 3 to 6", key, steps)
		}
		if cues := got.length(p + "cues"); cues < 1 || cues > 2 {
			t.Errorf("%s has %d cues, want 1 or 2", key, cues)
		}
		switch photos := got.length(p + "imageUrls"); photos {
		case 0:
		case 2:
			withPhotos++
		default:
			t.Errorf("%s has %d photos, want 0 or 2", key, photos)
		}
	}
	if withPhotos != 28 {
		t.Fatalf("%d exercises have photos, want 28", withPhotos)
	}
	i := exerciseIndex(t, got, "push_up")
	if got.str(fmt.Sprintf("exercises.%d.imageUrls.1", i)) != "/api/exercises/push_up/images/1" {
		t.Fatalf("push-up photos = %s", got.Body)
	}
	if got.length(fmt.Sprintf("exercises.%d.imageUrls", exerciseIndex(t, got, "burpee"))) != 0 {
		t.Fatalf("burpee must have no photo: %s", got.Body)
	}
}

func TestExercisePhotosAreServedWithLongCaching(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	for i := 0; i < got.length("exercises"); i++ {
		for j := 0; j < got.length(fmt.Sprintf("exercises.%d.imageUrls", i)); j++ {
			url := got.str(fmt.Sprintf("exercises.%d.imageUrls.%d", i, j))
			img := h.get(url, nick.Token).expect(http.StatusOK)
			if img.Header.Get("Content-Type") != "image/jpeg" || len(img.Body) < 1000 || len(img.Body) > maxImageBytes {
				t.Errorf("%s: type %q, %d bytes", url, img.Header.Get("Content-Type"), len(img.Body))
			}
			if !strings.Contains(img.Header.Get("Cache-Control"), "max-age=2592000") {
				t.Errorf("%s: Cache-Control = %q", url, img.Header.Get("Cache-Control"))
			}
		}
	}

	url := "/api/exercises/push_up/images/0"
	first := h.get(url, nick.Token).expect(http.StatusOK)
	etag := first.Header.Get("ETag")
	if etag == "" {
		t.Fatal("photo has no ETag")
	}
	h.get(url, nick.Token, func(r *http.Request) { r.Header.Set("If-None-Match", etag) }).expect(http.StatusNotModified)
}

func TestExercisePhotoRoutesStayGuarded(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.get("/api/exercises/push_up/images/0", "").expect(http.StatusUnauthorized)
	h.get("/api/exercises/push_up/images/0", nick.Token, func(r *http.Request) { r.Header.Del("X-App-Key") }).
		expect(http.StatusForbidden)
	h.get("/api/exercises/push_up/images/2", nick.Token).expect(http.StatusNotFound)
	h.get("/api/exercises/push_up/images/-1", nick.Token).expect(http.StatusNotFound)
	h.get("/api/exercises/push_up/images/x", nick.Token).expect(http.StatusNotFound)
	h.get("/api/exercises/burpee/images/0", nick.Token).expect(http.StatusNotFound)
	h.get("/api/exercises/nope/images/0", nick.Token).expect(http.StatusNotFound)
}

func TestCustomExercisesHaveNoHowTo(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	made := h.post("/api/exercises", nick.Token, obj{"name": "Sled push", "primaryMuscles": []string{"quads"},
		"measure": "reps", "load": "external"}).expect(http.StatusCreated)
	if made.length("exercise.steps") != 0 || made.length("exercise.cues") != 0 || made.length("exercise.imageUrls") != 0 {
		t.Fatalf("custom exercise how-to = %s", made.Body)
	}
}

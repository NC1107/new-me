package together

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
)

const (
	// HeldPushLife is how long a held push stays worth sending; an older one is dropped.
	HeldPushLife = 24 * time.Hour
	// heldStoreTimeout bounds the write of a held push from a request path.
	heldStoreTimeout = 3 * time.Second
)

// hold stores a push that cannot be sent now, for delivery at or after the given time.
func (s *Service) hold(to db.User, m push.Message, after time.Time) Delivery {
	if s.DB == nil {
		return NotSent
	}
	ctx, cancel := context.WithTimeout(context.Background(), heldStoreTimeout)
	defer cancel()
	err := db.InsertHeldPush(ctx, s.DB.Pool, db.HeldPush{UserID: to.ID, Kind: m.Kind, Title: m.Title, Body: m.Body,
		CreatedAt: s.now(), DeliverAfter: after})
	if err != nil {
		log.Printf("[NEWME] hold %s push for user %d: %v", m.Kind, to.ID, err)
		return NotSent
	}
	return Deferred
}

// heldSubject identifies what a held push is about, so repeats collapse into one.
type heldSubject struct {
	userID      int64
	kind, title string
	body        string
}

// DeliverHeld sends the held pushes that have come due. It drops those older than HeldPushLife,
// and those whose switch was turned off since; it sends one push per recipient, kind and subject
// however many were held; and it holds a push again if the person is still in a quiet moment (an
// away span began meanwhile). A refused enqueue leaves the push for the next pass.
func (s *Service) DeliverHeld(ctx context.Context) error {
	now := s.now()
	if err := db.ExpireHeldPushes(ctx, s.DB.Pool, now.Add(-HeldPushLife)); err != nil {
		return err
	}
	if s.Notifier == nil {
		return nil
	}
	due, err := db.DueHeldPushes(ctx, s.DB.Pool, now)
	if err != nil || len(due) == 0 {
		return err
	}
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	byID := map[int64]db.User{}
	for _, u := range users {
		byID[u.ID] = u
	}
	var order []heldSubject
	groups := map[heldSubject][]db.HeldPush{}
	for _, h := range due {
		key := heldSubject{h.UserID, h.Kind, h.Title, h.Body}
		if _, seen := groups[key]; !seen {
			order = append(order, key)
		}
		groups[key] = append(groups[key], h)
	}
	var errs []error
	for _, key := range order {
		if err := s.deliverHeldGroup(ctx, byID[key.userID], groups[key], now); err != nil {
			errs = append(errs, fmt.Errorf("held %s for user %d: %w", key.kind, key.userID, err))
		}
	}
	return errors.Join(errs...)
}

func (s *Service) deliverHeldGroup(ctx context.Context, to db.User, group []db.HeldPush, now time.Time) error {
	ids := make([]int64, len(group))
	for i, h := range group {
		ids[i] = h.ID
	}
	last := group[len(group)-1]
	if to.ID == 0 || !wants(to.Notify, last.Kind) {
		return db.DeleteHeldPushes(ctx, s.DB.Pool, ids)
	}
	if held, after := s.holdUntil(to, last.Kind); held {
		return db.DeferHeldPushes(ctx, s.DB.Pool, ids, after)
	}
	if !s.Notifier.Enqueue(push.Message{UserID: to.ID, Kind: last.Kind, Title: last.Title, Body: last.Body}) {
		return nil
	}
	return db.MarkHeldDelivered(ctx, s.DB.Pool, ids, now)
}

package together

import (
	"context"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
)

// Claim is a row of notice_log: the push kind (or a finer key) sent for a person's local day.
type Claim struct {
	Kind   string
	UserID int64
	Date   score.Date
}

// Wants reports whether a push of the kind may reach the person at this moment: push is on,
// they have not switched the event off, and it is not a quiet hour or an away day.
func (s *Service) Wants(to db.User, kind string) bool {
	return s.Notifier != nil && wants(to.Notify, kind) && !s.Held(to, kind)
}

// SendClaimed delivers a message at most once per claim. It does nothing, and claims nothing,
// when the person would not get the push right now, so a later pass can try again inside their
// window. The claim is released when the dispatcher refuses the message, so the same pass on
// the next run sends it. The claim owner can be someone other than the recipient, as when one
// person's finished day is announced to the other.
func (s *Service) SendClaimed(ctx context.Context, claim Claim, to db.User, m push.Message) (Delivery, error) {
	if !s.Wants(to, m.Kind) {
		return NotSent, nil
	}
	first, err := db.ClaimNotice(ctx, s.DB.Pool, claim.Kind, claim.UserID, claim.Date)
	if err != nil || !first {
		return NotSent, err
	}
	m.UserID = to.ID
	if s.Notifier.Enqueue(m) {
		return Queued, nil
	}
	if err := db.ReleaseNotice(ctx, s.DB.Pool, claim.Kind, claim.UserID, claim.Date); err != nil {
		return Failed, err
	}
	return Failed, nil
}

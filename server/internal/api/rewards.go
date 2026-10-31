package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/gems"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

const (
	codeRewardNotReached = "reward_not_reached"
	codeRewardState      = "reward_state"
	codeWishlistFull     = "wishlist_full"
	codeInsufficient     = "insufficient_gems"
	codeTreatsFull       = "treats_full"

	// priceHelperDays is how far back the pair's own pace is read.
	priceHelperDays = 14
	maxWishlist     = 50
)

var errNoReward = newErr(http.StatusNotFound, codeNotFound, "no such reward")

type rewardJSON struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	// Price is in gems. Target repeats it for builds from before shared rewards.
	Price    int `json:"price"`
	Target   int `json:"target"`
	Progress int `json:"progress"`
	// Status is pending, declined, approved or claimed.
	Status         string `json:"status"`
	Focus          bool   `json:"focus"`
	Ready          bool   `json:"ready"`
	ProposedBy     *int64 `json:"proposedBy"`
	ProposedByName string `json:"proposedByName"`
	CreatedBy      *int64 `json:"createdBy"`
	// OwnerID and OwnerName are set on a treat, which only its owner redeems.
	OwnerID   *int64  `json:"ownerId"`
	OwnerName string  `json:"ownerName"`
	StartedAt string  `json:"startedAt"`
	ReachedAt *string `json:"reachedAt"`
	ClaimedAt *string `json:"claimedAt"`
}

// rewardView renders rewards against one reading of the bank and the people's names.
type rewardView struct {
	bank   int
	names  map[int64]string
	people db.PersonGems
}

func (s *Server) rewardView(ctx context.Context) (rewardView, error) {
	people, err := db.ReadPersonGems(ctx, s.db.Pool)
	if err != nil {
		return rewardView{}, err
	}
	users, err := db.ListUsers(ctx, s.db.Pool)
	if err != nil {
		return rewardView{}, err
	}
	names := make(map[int64]string, len(users))
	for _, u := range users {
		names[u.ID] = u.Name
	}
	return rewardView{bank: gems.Bank(people.Gems()), names: names, people: people}, nil
}

func (v rewardView) json(r db.Reward) rewardJSON {
	funds := v.bank
	if r.OwnerID != nil {
		owner, _ := v.people.Find(*r.OwnerID)
		funds = owner.Balance()
	}
	progress := together.RewardProgress(funds, r.Price)
	if r.Status == db.RewardClaimed {
		progress = r.Price
	}
	out := rewardJSON{ID: r.ID, Name: r.Name, Price: r.Price, Target: r.Price, Progress: progress,
		Status: r.Status, Focus: r.Focus, Ready: r.Status == db.RewardApproved && together.RewardReady(funds, r.Price),
		OwnerID:    r.OwnerID,
		ProposedBy: r.ProposedBy, CreatedBy: r.ProposedBy, StartedAt: wireTime(r.StartedAt),
		ReachedAt: wireTimePtr(r.ReachedAt), ClaimedAt: wireTimePtr(r.ClaimedAt)}
	if r.ProposedBy != nil {
		out.ProposedByName = v.names[*r.ProposedBy]
	}
	if r.OwnerID != nil {
		out.OwnerName = v.names[*r.OwnerID]
	}
	return out
}

type balanceJSON struct {
	UserID  int64  `json:"userId"`
	Name    string `json:"name"`
	Earned  int    `json:"earned"`
	Paid    int    `json:"paid"`
	Balance int    `json:"balance"`
}

// balances is each person's own gems, the figures treats are paid from.
func (v rewardView) balances() []balanceJSON {
	out := make([]balanceJSON, len(v.people))
	for i, p := range v.people {
		out[i] = balanceJSON{UserID: p.UserID, Name: p.Name, Earned: p.Earned, Paid: p.Paid, Balance: p.Balance()}
	}
	return out
}

type redemptionJSON struct {
	ID         int64  `json:"id"`
	TreatID    *int64 `json:"treatId"`
	UserID     int64  `json:"userId"`
	UserName   string `json:"userName"`
	Name       string `json:"name"`
	Price      int    `json:"price"`
	RedeemedAt string `json:"redeemedAt"`
}

func (v rewardView) redemption(r db.Redemption) redemptionJSON {
	return redemptionJSON{ID: r.ID, TreatID: r.TreatID, UserID: r.UserID, UserName: v.names[r.UserID],
		Name: r.Name, Price: r.Price, RedeemedAt: wireTime(r.CreatedAt)}
}

// focusRewardJSON is the reward /board shows for builds that only know one: the focus.
func (s *Server) focusRewardJSON(ctx context.Context) (*rewardJSON, error) {
	r, err := db.FocusReward(ctx, s.db.Pool)
	if errors.Is(err, db.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	view, err := s.rewardView(ctx)
	if err != nil {
		return nil, err
	}
	out := view.json(r)
	return &out, nil
}

type priceOptionJSON struct {
	Days  int `json:"days"`
	Price int `json:"price"`
}

type priceHelpJSON struct {
	MedianDaily int               `json:"medianDaily"`
	SampleDays  int               `json:"sampleDays"`
	Options     []priceOptionJSON `json:"options"`
}

// priceHelp reads the pair's last full days of combined gems, ending yesterday on the
// caller's calendar, and turns them into suggested prices. It is nil without history.
func (s *Server) priceHelp(ctx context.Context, c caller) (*priceHelpJSON, error) {
	loc, err := c.user.Location()
	if err != nil {
		return nil, err
	}
	today := score.LocalToday(s.now(), loc)
	daily, err := db.DailyGems(ctx, s.db.Pool, today.AddDays(-priceHelperDays), today.AddDays(-1))
	if err != nil {
		return nil, err
	}
	help := together.SuggestPrices(daily)
	if help == nil {
		return nil, nil
	}
	out := &priceHelpJSON{MedianDaily: help.MedianDaily, SampleDays: help.SampleDays,
		Options: make([]priceOptionJSON, len(help.Options))}
	for i, o := range help.Options {
		out.Options[i] = priceOptionJSON{Days: o.Days, Price: o.Price}
	}
	return out, nil
}

// handleListRewards answers the wishlist (everything open, focus first), the claimed history,
// the gem bank and the price helper. Reward is the focus, for builds that know only one.
func (s *Server) handleListRewards(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	s.together.SettleQuietly(ctx)
	view, err := s.rewardView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	open, err := db.ListOpenRewards(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	claimed, err := db.ListClaimedRewards(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	help, err := s.priceHelp(ctx, callerFrom(r))
	if err != nil {
		fail(w, r, err)
		return
	}
	var focus *rewardJSON
	wishlist := make([]rewardJSON, len(open))
	for i, rw := range open {
		wishlist[i] = view.json(rw)
		if rw.Focus {
			focus = &wishlist[i]
		}
	}
	history := make([]rewardJSON, len(claimed))
	for i, rw := range claimed {
		history[i] = view.json(rw)
	}
	treatRows, err := db.ListTreats(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	treats := make([]rewardJSON, len(treatRows))
	for i, t := range treatRows {
		treats[i] = view.json(t)
	}
	redemptions, err := db.ListRedemptions(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	treatHistory := make([]redemptionJSON, len(redemptions))
	for i, red := range redemptions {
		treatHistory[i] = view.redemption(red)
	}
	writeJSON(w, http.StatusOK, map[string]any{"reward": focus, "rewards": wishlist, "history": history,
		"bank": view.bank, "priceHelp": help, "treats": treats, "treatHistory": treatHistory,
		"balances": view.balances()})
}

type rewardRequest struct {
	Name   *string `json:"name"`
	Price  *int    `json:"price"`
	Target *int    `json:"target"`
	// Treat proposes a personal treat for the caller instead of a shared reward.
	Treat bool `json:"treat"`
}

// price is the requested price, with the pre-v13 field name as a fallback.
func (q rewardRequest) price() *int {
	if q.Price != nil {
		return q.Price
	}
	return q.Target
}

func checkPrice(price int) *httpError {
	if price < 1 || price > together.MaxRewardPrice {
		return invalid(fmt.Sprintf("price must be between 1 and %d gems", together.MaxRewardPrice))
	}
	return nil
}

func rewardID(r *http.Request) (int64, *httpError) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		return 0, errNoReward
	}
	return id, nil
}

func rewardStateErr(msg string) *httpError {
	return newErr(http.StatusConflict, codeRewardState, msg)
}

// notifyRewardProposal tells the partner that a reward or a new price waits for their answer.
func (s *Server) notifyRewardProposal(to, from db.User, r db.Reward) {
	title, body := "Reward to approve", fmt.Sprintf("%s wants %s for %d gems", from.Name, r.Name, r.Price)
	if r.OwnerID != nil {
		title, body = "Treat to approve", fmt.Sprintf("%s wants %s as a treat for %d gems", from.Name, r.Name, r.Price)
	}
	s.together.Notify(to, push.Message{Kind: together.EventRewardProposal, Title: title, Body: body})
}

// handleCreateReward proposes a reward. The partner approves it; alone, it is approved at once.
func (s *Server) handleCreateReward(w http.ResponseWriter, r *http.Request) {
	var req rewardRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Name == nil || req.price() == nil {
		fail(w, r, invalid("name and price are required"))
		return
	}
	name, herr := cleanName(*req.Name)
	if herr != nil {
		fail(w, r, invalid("name must be 1 to 40 characters without control characters"))
		return
	}
	if herr := checkPrice(*req.price()); herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	// Builds from before shared rewards send only target and have no approval UI, so a reward
	// they create is approved at once rather than left pending where they cannot see it.
	legacy := req.Price == nil
	status := db.RewardPending
	if partner == nil || legacy {
		status = db.RewardApproved
	}
	var owner *int64
	if req.Treat {
		owner = &c.user.ID
	}
	var reward db.Reward
	duplicate := false
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockRewards(ctx, tx); err != nil {
			return err
		}
		existing, err := db.PendingRewardByName(ctx, tx, c.user.ID, owner, name)
		if err == nil {
			reward, duplicate = existing, true
			return nil
		}
		if !errors.Is(err, db.ErrNotFound) {
			return err
		}
		if owner != nil {
			n, err := db.CountOpenTreats(ctx, tx, *owner)
			if err != nil {
				return err
			}
			if n >= gems.MaxTreatsPerPerson {
				return newErr(http.StatusConflict, codeTreatsFull, "you have too many treats")
			}
		} else {
			n, err := db.CountOpenRewards(ctx, tx)
			if err != nil {
				return err
			}
			if n >= maxWishlist {
				return newErr(http.StatusConflict, codeWishlistFull, "the wishlist is full")
			}
		}
		reward, err = db.InsertReward(ctx, tx, name, *req.price(), c.user.ID, owner, status)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if duplicate {
		s.writeReward(w, r, http.StatusOK, reward)
		return
	}
	if partner != nil && status == db.RewardPending {
		s.notifyRewardProposal(*partner, c.user, reward)
	}
	s.writeReward(w, r, http.StatusCreated, reward)
}

func (s *Server) writeReward(w http.ResponseWriter, r *http.Request, status int, reward db.Reward) {
	view, err := s.rewardView(r.Context())
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, status, map[string]any{"reward": view.json(reward), "bank": view.bank, "balances": view.balances()})
}

// changeReward runs one locked change to a reward and answers with it. The change returns the
// reward to save and whether its price changed, or an error to refuse.
func (s *Server) changeReward(w http.ResponseWriter, r *http.Request,
	change func(tx pgx.Tx, rw db.Reward, partner *db.User) (db.Reward, bool, *httpError)) {
	id, herr := rewardID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	var saved, before db.Reward
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		rw, err := db.LockReward(ctx, tx, id)
		if errors.Is(err, db.ErrNotFound) {
			return errNoReward
		}
		if err != nil {
			return err
		}
		before = rw
		next, priceChanged, herr := change(tx, rw, partner)
		if herr != nil {
			return herr
		}
		saved, err = db.SaveReward(ctx, tx, next, priceChanged)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	// A pending proposal is announced when it becomes one or its price moves, not on a rename.
	if saved.Status == db.RewardPending && partner != nil && (before.Status != db.RewardPending || before.Price != saved.Price) {
		s.notifyRewardProposal(*partner, c.user, saved)
	}
	s.writeReward(w, r, http.StatusOK, saved)
}

func proposedByMe(rw db.Reward, c caller) bool {
	return rw.ProposedBy != nil && *rw.ProposedBy == c.user.ID
}

// handlePatchReward edits a reward. The proposer edits a pending or declined one in place (a
// declined one is proposed again). Either person renames an approved one, but a new price on an
// approved reward is proposed again and waits for the other person.
func (s *Server) handlePatchReward(w http.ResponseWriter, r *http.Request) {
	var req rewardRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	s.changeReward(w, r, func(_ pgx.Tx, rw db.Reward, partner *db.User) (db.Reward, bool, *httpError) {
		if req.Name != nil {
			if rw.OwnerID != nil && *rw.OwnerID != c.user.ID {
				return rw, false, newErr(http.StatusForbidden, codeForbidden, "only the owner renames a treat")
			}
			name, herr := cleanName(*req.Name)
			if herr != nil {
				return rw, false, invalid("name must be 1 to 40 characters without control characters")
			}
			rw.Name = name
		}
		priceChanged := false
		before := rw.Price
		if p := req.price(); p != nil {
			if herr := checkPrice(*p); herr != nil {
				return rw, false, herr
			}
			priceChanged = *p != rw.Price
			rw.Price = *p
		}
		switch rw.Status {
		case db.RewardPending, db.RewardDeclined:
			if !proposedByMe(rw, c) {
				return rw, false, newErr(http.StatusForbidden, codeForbidden, "only the proposer can edit a pending reward")
			}
			if partner != nil {
				rw.Status = db.RewardPending
			} else {
				rw.Status = db.RewardApproved
				rw.ApprovedPrice, rw.ApprovedFocus = nil, false
			}
		case db.RewardApproved:
			if priceChanged {
				rw.ProposedBy = &c.user.ID
				if partner != nil {
					rw.ApprovedPrice, rw.ApprovedFocus = &before, rw.Focus
					rw.Focus = false
					rw.Status = db.RewardPending
				}
			}
		default:
			return rw, false, errNoReward
		}
		return rw, priceChanged, nil
	})
}

// revertPriceChange puts back the approved state a pending price change replaced. The focus
// comes back only while the slot is free, which SaveReward checks.
func revertPriceChange(rw db.Reward) db.Reward {
	rw.Price, rw.Status, rw.Focus = *rw.ApprovedPrice, db.RewardApproved, rw.ApprovedFocus
	rw.ApprovedPrice, rw.ApprovedFocus = nil, false
	return rw
}

// handleWithdrawReward deletes a reward its proposer made that was never approved. Withdrawing a
// new price on an approved reward restores the approved reward and its price instead.
func (s *Server) handleWithdrawReward(w http.ResponseWriter, r *http.Request) {
	id, herr := rewardID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		rw, err := db.LockReward(ctx, tx, id)
		if errors.Is(err, db.ErrNotFound) {
			return errNoReward
		}
		if err != nil {
			return err
		}
		if rw.Status != db.RewardPending && rw.Status != db.RewardDeclined {
			return rewardStateErr("only a pending reward can be withdrawn; cancel an approved one instead")
		}
		if !proposedByMe(rw, c) {
			return newErr(http.StatusForbidden, codeForbidden, "only the proposer can withdraw a reward")
		}
		if rw.ApprovedPrice != nil {
			_, err := db.SaveReward(ctx, tx, revertPriceChange(rw), true)
			return err
		}
		return db.DeleteReward(ctx, tx, id)
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleApproveReward(w http.ResponseWriter, r *http.Request) {
	s.answerReward(w, r, true)
}
func (s *Server) handleDeclineReward(w http.ResponseWriter, r *http.Request) {
	s.answerReward(w, r, false)
}

// answerReward lets the person who did not propose a pending reward approve or decline it.
// Approving makes it the focus when there is none.
func (s *Server) answerReward(w http.ResponseWriter, r *http.Request, approve bool) {
	c := callerFrom(r)
	s.changeReward(w, r, func(_ pgx.Tx, rw db.Reward, _ *db.User) (db.Reward, bool, *httpError) {
		if rw.Status != db.RewardPending {
			return rw, false, rewardStateErr("that reward is not waiting for an answer")
		}
		if proposedByMe(rw, c) {
			return rw, false, newErr(http.StatusForbidden, codeForbidden, "the other person answers a proposal")
		}
		if approve {
			rw.Status, rw.Focus = db.RewardApproved, rw.ApprovedFocus
			rw.ApprovedPrice, rw.ApprovedFocus = nil, false
		} else if rw.ApprovedPrice != nil {
			return revertPriceChange(rw), true, nil
		} else {
			rw.Status = db.RewardDeclined
		}
		return rw, false, nil
	})
}

// handleCancelReward drops an approved reward from the wishlist; either person may, except that a
// treat is removed by its owner.
func (s *Server) handleCancelReward(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	s.changeReward(w, r, func(_ pgx.Tx, rw db.Reward, _ *db.User) (db.Reward, bool, *httpError) {
		if rw.OwnerID != nil && *rw.OwnerID != c.user.ID {
			return rw, false, newErr(http.StatusForbidden, codeForbidden, "only the owner removes a treat")
		}
		if rw.Status != db.RewardApproved {
			return rw, false, rewardStateErr("only an approved reward can be cancelled")
		}
		rw.Status = db.RewardCancelled
		return rw, false, nil
	})
}

// handleFocusReward makes an approved reward the bar on Us.
func (s *Server) handleFocusReward(w http.ResponseWriter, r *http.Request) {
	id, herr := rewardID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	var focus db.Reward
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		rw, err := db.LockReward(ctx, tx, id)
		if errors.Is(err, db.ErrNotFound) {
			return errNoReward
		}
		if err != nil {
			return err
		}
		if rw.Status != db.RewardApproved || rw.OwnerID != nil {
			return rewardStateErr("only an approved shared reward can be the focus")
		}
		focus, err = db.SetFocus(ctx, tx, id)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	s.writeReward(w, r, http.StatusOK, focus)
}

// handleClaimReward spends the price of a ready reward from the bank. Claiming again returns
// the claimed reward and spends nothing.
func (s *Server) handleClaimReward(w http.ResponseWriter, r *http.Request) {
	id, herr := rewardID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	s.together.SettleQuietly(ctx)
	var claimed db.Reward
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		claimed, err = db.ClaimReward(ctx, tx, id)
		return err
	})
	switch {
	case errors.Is(err, db.ErrNotFound):
		fail(w, r, errNoReward)
	case errors.Is(err, db.ErrRewardNotReady):
		fail(w, r, newErr(http.StatusConflict, codeRewardNotReached, "the gem bank does not cover that reward yet"))
	case errors.Is(err, db.ErrRewardState):
		fail(w, r, rewardStateErr("only an approved reward can be claimed"))
	case err != nil:
		fail(w, r, err)
	default:
		s.writeReward(w, r, http.StatusOK, claimed)
	}
}

type redeemRequest struct {
	// RequestID is made once per tap by the app, so a retry or a double tap redeems once.
	RequestID string `json:"requestId"`
}

// handleRedeemTreat spends the price of the caller's own treat from their own balance and tells
// the partner. Redeeming again with the same request id returns the first redemption.
func (s *Server) handleRedeemTreat(w http.ResponseWriter, r *http.Request) {
	id, herr := rewardID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	var req redeemRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if n := len(req.RequestID); n < 8 || n > 64 {
		fail(w, r, invalid("requestId must be 8 to 64 characters"))
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	var red db.Redemption
	created := false
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		red, created, err = db.RedeemTreat(ctx, tx, c.user.ID, id, req.RequestID)
		return err
	})
	switch {
	case errors.Is(err, db.ErrNotFound):
		fail(w, r, errNoReward)
		return
	case errors.Is(err, db.ErrNotTreatOwner):
		fail(w, r, newErr(http.StatusForbidden, codeForbidden, "that treat belongs to the other person"))
		return
	case errors.Is(err, db.ErrInsufficientGems):
		fail(w, r, newErr(http.StatusConflict, codeInsufficient, "your own gems do not cover that treat yet"))
		return
	case errors.Is(err, db.ErrRewardState):
		fail(w, r, rewardStateErr("only an approved treat can be redeemed"))
		return
	case err != nil:
		fail(w, r, err)
		return
	}
	if created {
		if partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID); err == nil && partner != nil {
			s.together.Notify(*partner, push.Message{Kind: together.EventTreat, Title: "Treat redeemed",
				Body: fmt.Sprintf("%s redeemed %s", c.user.Name, red.Name)})
		}
	}
	view, err := s.rewardView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	treat, err := db.GetReward(ctx, s.db.Pool, id)
	if err != nil {
		fail(w, r, err)
		return
	}
	status := http.StatusCreated
	if !created {
		status = http.StatusOK
	}
	writeJSON(w, status, map[string]any{"redemption": view.redemption(red), "reward": view.json(treat),
		"bank": view.bank, "balances": view.balances()})
}

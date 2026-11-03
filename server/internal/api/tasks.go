package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/tasks"
	"github.com/nc1107/new-me/server/internal/together"
)

const (
	codeTaskState = "task_state"
	codeTasksFull = "tasks_full"
)

var errNoTask = newErr(http.StatusNotFound, codeNotFound, "no such task")

func taskStateErr(msg string) *httpError { return newErr(http.StatusConflict, codeTaskState, msg) }

type taskJSON struct {
	ID           int64  `json:"id"`
	Title        string `json:"title"`
	CreatorID    int64  `json:"creatorId"`
	CreatorName  string `json:"creatorName"`
	AssigneeID   int64  `json:"assigneeId"`
	AssigneeName string `json:"assigneeName"`
	// Stake is what the task is worth in gems: earned when it is done in time.
	Stake int `json:"stake"`
	// LoseIfMissed is the assignee's opt-in to lose gems on a miss; Lost is what the miss took.
	LoseIfMissed bool `json:"loseIfMissed"`
	Lost         int  `json:"lost"`
	// Deadline is the last day it counts, as YYYY-MM-DD on the assignee's calendar.
	Deadline string `json:"deadline"`
	// DaysLeft counts from the assignee's today to the deadline: 0 is due today, negative is overdue.
	DaysLeft  int     `json:"daysLeft"`
	Status    string  `json:"status"`
	CreatedAt string  `json:"createdAt"`
	AgreedAt  *string `json:"agreedAt"`
	SettledAt *string `json:"settledAt"`
}

// taskView renders tasks against the people and the clock.
type taskView struct {
	users map[int64]db.User
	now   time.Time
}

func (s *Server) taskView(ctx context.Context) (taskView, error) {
	users, err := db.ListUsers(ctx, s.db.Pool)
	if err != nil {
		return taskView{}, err
	}
	byID := make(map[int64]db.User, len(users))
	for _, u := range users {
		byID[u.ID] = u
	}
	return taskView{users: byID, now: s.now()}, nil
}

// today is the assignee's current calendar day.
func (v taskView) today(assigneeID int64) (score.Date, error) {
	loc, err := v.users[assigneeID].Location()
	if err != nil {
		return "", err
	}
	return score.LocalToday(v.now, loc), nil
}

func (v taskView) json(t db.Task) (taskJSON, error) {
	today, err := v.today(t.AssigneeID)
	if err != nil {
		return taskJSON{}, err
	}
	return taskJSON{ID: t.ID, Title: t.Title, CreatorID: t.CreatorID, CreatorName: v.users[t.CreatorID].Name,
		AssigneeID: t.AssigneeID, AssigneeName: v.users[t.AssigneeID].Name, Stake: t.Stake, LoseIfMissed: t.LoseIfMissed, Lost: t.Lost,
		Deadline: string(t.Deadline), DaysLeft: score.DaysBetween(today, t.Deadline), Status: t.Status,
		CreatedAt: wireTime(t.CreatedAt), AgreedAt: wireTimePtr(t.AgreedAt), SettledAt: wireTimePtr(t.SettledAt)}, nil
}

func (v taskView) jsonAll(list []db.Task) ([]taskJSON, error) {
	out := make([]taskJSON, len(list))
	for i, t := range list {
		j, err := v.json(t)
		if err != nil {
			return nil, err
		}
		out[i] = j
	}
	return out, nil
}

func taskID(r *http.Request) (int64, *httpError) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		return 0, errNoTask
	}
	return id, nil
}

// handleListTasks answers the open tasks of both people, the newest finished ones and the
// balances, after settling any task whose deadline has passed.
func (s *Server) handleListTasks(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	s.together.SettleQuietly(ctx)
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	open, err := db.ListOpenTasks(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	history, err := db.ListTaskHistory(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	openJSON, err := view.jsonAll(open)
	if err != nil {
		fail(w, r, err)
		return
	}
	historyJSON, err := view.jsonAll(history)
	if err != nil {
		fail(w, r, err)
		return
	}
	rv, err := s.rewardView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tasks": openJSON, "history": historyJSON,
		"bank": rv.bank, "balances": rv.balances()})
}

type taskRequest struct {
	Title      *string `json:"title"`
	AssigneeID *int64  `json:"assigneeId"`
	Stake      *int    `json:"stake"`
	Deadline   *string `json:"deadline"`
	// LoseIfMissed is only for a task the person takes on for themselves.
	LoseIfMissed *bool `json:"loseIfMissed"`
}

// apply writes the request's fields over the task and validates the result against the people
// who can hold it and the assignee's calendar.
func (q taskRequest) apply(t db.Task, view taskView, partner *db.User, self int64) (db.Task, *httpError) {
	if q.Title != nil {
		title, herr := cleanTaskTitle(*q.Title)
		if herr != nil {
			return t, herr
		}
		t.Title = title
	}
	if q.AssigneeID != nil {
		t.AssigneeID = *q.AssigneeID
	}
	if t.AssigneeID != self && (partner == nil || t.AssigneeID != partner.ID) {
		return t, invalid("a task is for you or your partner")
	}
	if q.LoseIfMissed != nil {
		t.LoseIfMissed = *q.LoseIfMissed
	}
	if t.AssigneeID != t.CreatorID {
		if q.LoseIfMissed != nil && *q.LoseIfMissed {
			return t, invalid("only a task you take on for yourself can cost you gems")
		}
		t.LoseIfMissed = false
	}
	if q.Stake != nil {
		t.Stake = *q.Stake
	}
	if t.Stake < 1 || t.Stake > tasks.MaxStake {
		return t, invalid(fmt.Sprintf("a task is worth between 1 and %d gems", tasks.MaxStake))
	}
	if q.Deadline != nil {
		d, err := score.ParseDate(*q.Deadline)
		if err != nil {
			return t, invalid("deadline must be a date like 2026-11-03")
		}
		t.Deadline = d
	}
	today, err := view.today(t.AssigneeID)
	if err != nil {
		return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
	}
	if tasks.Overdue(t.Deadline, today) {
		return t, invalid("the deadline cannot be before today")
	}
	if score.DaysBetween(today, t.Deadline) > tasks.MaxDaysAhead {
		return t, invalid("the deadline is too far away")
	}
	return t, nil
}

func cleanTaskTitle(raw string) (string, *httpError) {
	title := strings.TrimSpace(raw)
	if n := len([]rune(title)); n < 1 || n > tasks.MaxTitle || hasControlChars(title) {
		return "", invalid(fmt.Sprintf("title must be 1 to %d characters without control characters", tasks.MaxTitle))
	}
	return title, nil
}

// notifyTaskProposal asks the other person to agree to a task, in the same style as a reward.
func (s *Server) notifyTaskProposal(to, from db.User, t db.Task) {
	due := t.Deadline.Time().Format("Mon Jan 2")
	body := fmt.Sprintf("%s will %s for %d gems by %s", from.Name, t.Title, t.Stake, due)
	if t.LoseIfMissed {
		body += ", and will lose them if it is missed"
	}
	if t.AssigneeID == to.ID {
		body = fmt.Sprintf("%s asks you to do %q for %d gems by %s", from.Name, t.Title, t.Stake, due)
	}
	s.together.Notify(to, push.Message{Kind: together.EventTaskProposal, Title: "Task to agree on", Body: body})
}

func (s *Server) writeTask(w http.ResponseWriter, r *http.Request, status int, t db.Task) {
	ctx := r.Context()
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	j, err := view.json(t)
	if err != nil {
		fail(w, r, err)
		return
	}
	rv, err := s.rewardView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, status, map[string]any{"task": j, "bank": rv.bank, "balances": rv.balances()})
}

// handleCreateTask proposes a task. The other person agrees; alone, it is agreed at once.
func (s *Server) handleCreateTask(w http.ResponseWriter, r *http.Request) {
	var req taskRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Title == nil || req.Stake == nil || req.Deadline == nil {
		fail(w, r, invalid("title, gems and deadline are required"))
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	draft, herr := req.apply(db.Task{CreatorID: c.user.ID, AssigneeID: c.user.ID}, view, partner, c.user.ID)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	draft.Status = tasks.Proposed
	if partner == nil {
		draft.Status = tasks.Agreed
	}
	var saved db.Task
	duplicate := false
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if existing, err := db.FindProposedTask(ctx, tx, draft); err == nil {
			saved, duplicate = existing, true
			return nil
		} else if !errors.Is(err, db.ErrNotFound) {
			return err
		}
		n, err := db.CountOpenTasks(ctx, tx, c.user.ID)
		if err != nil {
			return err
		}
		if n >= tasks.MaxOpenPerPerson {
			return newErr(http.StatusConflict, codeTasksFull, "you have too many open tasks")
		}
		saved, err = db.InsertTask(ctx, tx, draft)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if duplicate {
		s.writeTask(w, r, http.StatusOK, saved)
		return
	}
	if partner != nil {
		s.notifyTaskProposal(*partner, c.user, saved)
	}
	s.writeTask(w, r, http.StatusCreated, saved)
}

// lockedTask runs one change to a task under its row lock and answers with the result. The change
// returns the task to save through its own query, or an error to refuse.
func (s *Server) lockedTask(w http.ResponseWriter, r *http.Request, change func(tx pgx.Tx, t db.Task) (db.Task, *httpError)) (db.Task, bool) {
	id, herr := taskID(r)
	if herr != nil {
		fail(w, r, herr)
		return db.Task{}, false
	}
	ctx := r.Context()
	var saved db.Task
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockRewards(ctx, tx); err != nil {
			return err
		}
		t, err := db.LockTask(ctx, tx, id)
		if errors.Is(err, db.ErrNotFound) {
			return errNoTask
		}
		if err != nil {
			return err
		}
		next, herr := change(tx, t)
		if herr != nil {
			return herr
		}
		saved = next
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return db.Task{}, false
	}
	return saved, true
}

func (s *Server) editableProposal(t db.Task, c caller) *httpError {
	if t.CreatorID != c.user.ID {
		return newErr(http.StatusForbidden, codeForbidden, "only the person who proposed a task changes it")
	}
	if t.Status != tasks.Proposed && t.Status != tasks.Declined {
		return taskStateErr("only a task that is still a proposal can be changed")
	}
	return nil
}

// handlePatchTask edits a proposal in place and proposes it again, which asks the other person
// once more.
func (s *Server) handlePatchTask(w http.ResponseWriter, r *http.Request) {
	var req taskRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	saved, ok := s.lockedTask(w, r, func(tx pgx.Tx, t db.Task) (db.Task, *httpError) {
		if herr := s.editableProposal(t, c); herr != nil {
			return t, herr
		}
		next, herr := req.apply(t, view, partner, c.user.ID)
		if herr != nil {
			return t, herr
		}
		next.Status = tasks.Proposed
		if partner == nil {
			next.Status = tasks.Agreed
		}
		saved, err := db.SaveTaskTerms(ctx, tx, next)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		return saved, nil
	})
	if !ok {
		return
	}
	if partner != nil && saved.Status == tasks.Proposed {
		s.notifyTaskProposal(*partner, c.user, saved)
	}
	s.writeTask(w, r, http.StatusOK, saved)
}

// handleWithdrawTask drops a proposal its creator made. An agreed task cannot be withdrawn: the
// gems are a promise both made.
func (s *Server) handleWithdrawTask(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	_, ok := s.lockedTask(w, r, func(tx pgx.Tx, t db.Task) (db.Task, *httpError) {
		if herr := s.editableProposal(t, c); herr != nil {
			return t, herr
		}
		saved, err := db.SetTaskStatus(r.Context(), tx, t.ID, tasks.Withdrawn, 0)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		return saved, nil
	})
	if ok {
		w.WriteHeader(http.StatusNoContent)
	}
}

// handleCounterTask answers a proposal with a different amount. The proposal then waits for the
// original proposer, who agrees or declines it like any other.
func (s *Server) handleCounterTask(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Stake *int `json:"stake"`
	}
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Stake == nil || *req.Stake < 1 || *req.Stake > tasks.MaxStake {
		fail(w, r, invalid(fmt.Sprintf("a task is worth between 1 and %d gems", tasks.MaxStake)))
		return
	}
	ctx := r.Context()
	c := callerFrom(r)
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	var original db.User
	saved, ok := s.lockedTask(w, r, func(tx pgx.Tx, t db.Task) (db.Task, *httpError) {
		if t.Status != tasks.Proposed {
			return t, taskStateErr("that task is not waiting for an answer")
		}
		if t.CreatorID == c.user.ID {
			return t, newErr(http.StatusForbidden, codeForbidden, "the other person answers a proposal")
		}
		today, err := view.today(t.AssigneeID)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		if !tasks.CanAnswer(t.Status, t.Deadline, today) {
			return t, taskStateErr("the deadline has passed")
		}
		original = view.users[t.CreatorID]
		saved, err := db.CounterTask(ctx, tx, t.ID, c.user.ID, *req.Stake)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		return saved, nil
	})
	if !ok {
		return
	}
	s.notifyTaskProposal(original, c.user, saved)
	s.writeTask(w, r, http.StatusOK, saved)
}

func (s *Server) handleAgreeTask(w http.ResponseWriter, r *http.Request)   { s.answerTask(w, r, true) }
func (s *Server) handleDeclineTask(w http.ResponseWriter, r *http.Request) { s.answerTask(w, r, false) }

// answerTask lets the person who did not propose a task agree to it or decline it. Agreeing makes
// it live; it needs the deadline to still be ahead.
func (s *Server) answerTask(w http.ResponseWriter, r *http.Request, agree bool) {
	ctx := r.Context()
	c := callerFrom(r)
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	saved, ok := s.lockedTask(w, r, func(tx pgx.Tx, t db.Task) (db.Task, *httpError) {
		if t.Status != tasks.Proposed {
			return t, taskStateErr("that task is not waiting for an answer")
		}
		if t.CreatorID == c.user.ID {
			return t, newErr(http.StatusForbidden, codeForbidden, "the other person answers a proposal")
		}
		next := tasks.Declined
		if agree {
			today, err := view.today(t.AssigneeID)
			if err != nil {
				return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
			}
			if !tasks.CanAnswer(t.Status, t.Deadline, today) {
				return t, taskStateErr("the deadline has passed")
			}
			next = tasks.Agreed
		}
		saved, err := db.SetTaskStatus(ctx, tx, t.ID, next, 0)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		return saved, nil
	})
	if ok {
		s.writeTask(w, r, http.StatusOK, saved)
	}
}

// handleFinishTask marks the caller's own agreed task done before its deadline day ends, which
// earns the gems. Finishing a done task again answers it unchanged and pushes nothing.
func (s *Server) handleFinishTask(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	c := callerFrom(r)
	view, err := s.taskView(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	finishedNow := false
	saved, ok := s.lockedTask(w, r, func(tx pgx.Tx, t db.Task) (db.Task, *httpError) {
		if t.AssigneeID != c.user.ID {
			return t, newErr(http.StatusForbidden, codeForbidden, "only the person a task is for marks it done")
		}
		if t.Status == tasks.Done {
			return t, nil
		}
		if t.Status == tasks.Missed {
			return t, taskStateErr("the deadline has passed")
		}
		today, err := view.today(t.AssigneeID)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		if t.Status == tasks.Agreed && tasks.Overdue(t.Deadline, today) {
			return t, taskStateErr("the deadline has passed")
		}
		if !tasks.CanFinish(t.Status, t.Deadline, today) {
			return t, taskStateErr("only an agreed task can be marked done")
		}
		saved, err := db.SetTaskStatus(ctx, tx, t.ID, tasks.Done, 0)
		if err != nil {
			return t, newErr(http.StatusInternalServerError, codeInternal, "server error")
		}
		finishedNow = true
		return saved, nil
	})
	if !ok {
		return
	}
	if finishedNow {
		if partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID); err == nil && partner != nil {
			s.together.Notify(*partner, push.Message{Kind: together.EventTask, Title: "Task done",
				Body: fmt.Sprintf("%s finished %s, +%d gems", c.user.Name, saved.Title, saved.Stake)})
		}
	}
	s.writeTask(w, r, http.StatusOK, saved)
}

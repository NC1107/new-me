package push

import (
	"context"
	"errors"
	"log"
	"sync"
)

// Sender delivers one alert to one device token.
type Sender interface {
	Send(ctx context.Context, deviceToken string, m Message) error
}

// Store is the token book the dispatcher reads and prunes.
type Store interface {
	Tokens(ctx context.Context, userID int64) ([]string, error)
	Remove(ctx context.Context, token string) error
}

// Dispatcher sends messages on background workers, so a slow or failing APNs can never delay
// or fail the request that triggered the notification.
type Dispatcher struct {
	sender Sender
	store  Store
	queue  chan Message
	wg     sync.WaitGroup
	cancel context.CancelFunc

	// mu guards closed, so a message is never sent on the closed queue.
	mu     sync.RWMutex
	closed bool
}

const (
	defaultWorkers = 2
	defaultQueue   = 64
)

// NewDispatcher starts workers that run until ctx ends or Shutdown is called. A full queue
// drops new messages.
func NewDispatcher(ctx context.Context, sender Sender, store Store) *Dispatcher {
	ctx, cancel := context.WithCancel(ctx)
	d := &Dispatcher{sender: sender, store: store, queue: make(chan Message, defaultQueue), cancel: cancel}
	for range defaultWorkers {
		d.wg.Add(1)
		go d.work(ctx)
	}
	return d
}

// Enqueue hands a message to the workers without waiting. It reports false when the queue is
// full or the dispatcher is shutting down and the message was dropped.
func (d *Dispatcher) Enqueue(m Message) bool {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.closed {
		log.Printf("[NEWME] push is shutting down, dropped %s for user %d", m.Kind, m.UserID)
		return false
	}
	select {
	case d.queue <- m:
		return true
	default:
		log.Printf("[NEWME] push queue full, dropped %s for user %d", m.Kind, m.UserID)
		return false
	}
}

// Wait blocks until the workers have stopped, which happens after their context ends.
func (d *Dispatcher) Wait() { d.wg.Wait() }

// Shutdown stops accepting messages, lets the workers deliver what is already queued and waits
// for them. When ctx ends first the remaining deliveries are cancelled and ctx's error is
// returned.
func (d *Dispatcher) Shutdown(ctx context.Context) error {
	d.mu.Lock()
	if !d.closed {
		d.closed = true
		close(d.queue)
	}
	d.mu.Unlock()
	done := make(chan struct{})
	go func() {
		d.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
		d.cancel()
		return nil
	case <-ctx.Done():
		d.cancel()
		<-done
		return ctx.Err()
	}
}

func (d *Dispatcher) work(ctx context.Context) {
	defer d.wg.Done()
	for {
		select {
		case <-ctx.Done():
			return
		case m, ok := <-d.queue:
			if !ok {
				return
			}
			d.deliver(ctx, m)
		}
	}
}

func (d *Dispatcher) deliver(ctx context.Context, m Message) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[NEWME] push panic: %v", r)
		}
	}()
	tokens, err := d.store.Tokens(ctx, m.UserID)
	if err != nil {
		log.Printf("[NEWME] push tokens for user %d: %v", m.UserID, err)
		return
	}
	for _, token := range tokens {
		err := d.sender.Send(ctx, token, m)
		switch {
		case err == nil:
		case errors.Is(err, ErrUnregistered):
			if rmErr := d.store.Remove(ctx, token); rmErr != nil {
				log.Printf("[NEWME] push remove token: %v", rmErr)
			}
		default:
			log.Printf("[NEWME] push %s to user %d: %v", m.Kind, m.UserID, err)
		}
	}
}

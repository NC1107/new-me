package main

import (
	"context"
	"fmt"
	"io"

	"github.com/nc1107/new-me/server/internal/auth"
	"github.com/nc1107/new-me/server/internal/db"
)

// runInvite mints a single-use code. Stdout carries only the code so it can be piped; the
// expiry goes to the other stream.
func runInvite(ctx context.Context, database *db.DB, stdout, stderr io.Writer) error {
	code, expiresAt, err := auth.IssueInvite(ctx, database.Pool, nil)
	if err != nil {
		return err
	}
	fmt.Fprintln(stdout, code)
	fmt.Fprintf(stderr, "single use, expires %s (%s)\n", expiresAt.Format("15:04:05 MST"), auth.InviteTTL)
	return nil
}

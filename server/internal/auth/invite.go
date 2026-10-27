package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
)

// InviteTTL is how long a freshly issued code stays redeemable.
const InviteTTL = 15 * time.Minute

// InviteCodeLen is the number of Crockford base32 symbols in a code: 16 symbols are 80 bits.
const InviteCodeLen = 16

const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// NewInviteCode returns a random code shown as XXXX-XXXX-XXXX-XXXX.
func NewInviteCode() (string, error) {
	raw := make([]byte, InviteCodeLen)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	var sb strings.Builder
	for i, b := range raw {
		if i > 0 && i%4 == 0 {
			sb.WriteByte('-')
		}
		// 32 symbols divide 256 evenly, so masking keeps the draw uniform.
		sb.WriteByte(crockford[b&31])
	}
	return sb.String(), nil
}

// NormalizeInviteCode upper-cases the input, drops separators and reads the look-alike letters
// the way Crockford base32 does. It returns "" for anything that cannot be a code.
func NormalizeInviteCode(s string) string {
	var sb strings.Builder
	for _, r := range strings.ToUpper(s) {
		switch {
		case r == '-' || r == ' ':
			continue
		case r == 'O':
			r = '0'
		case r == 'I' || r == 'L':
			r = '1'
		}
		if r > 127 || !strings.ContainsRune(crockford, r) {
			return ""
		}
		sb.WriteRune(r)
	}
	if sb.Len() != InviteCodeLen {
		return ""
	}
	return sb.String()
}

// HashInviteCode is the hex SHA-256 of the normalized code, which is all that is stored.
// A malformed code hashes to a value no invite has.
func HashInviteCode(s string) string {
	sum := sha256.Sum256([]byte("invite:" + NormalizeInviteCode(s)))
	return hex.EncodeToString(sum[:])
}

// IssueInvite stores a fresh single-use code and returns the plaintext once. createdBy is nil
// for codes minted from the command line.
func IssueInvite(ctx context.Context, q db.Querier, createdBy *int64) (code string, expiresAt time.Time, err error) {
	code, err = NewInviteCode()
	if err != nil {
		return "", time.Time{}, err
	}
	expiresAt = time.Now().Add(InviteTTL).UTC()
	if err := db.CreateInvite(ctx, q, HashInviteCode(code), createdBy, InviteTTL); err != nil {
		return "", time.Time{}, err
	}
	return code, expiresAt, nil
}

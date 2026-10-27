-- Audiobookshelf listening: one linked account per user and the minutes it contributes per day.

-- The password is never stored. The tokens keep the server signed in; Audiobookshelf rotates the
-- refresh token on every refresh, so the stored one is always the newest.
CREATE TABLE audiobookshelf_accounts (
    user_id          BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    abs_user_id      TEXT NOT NULL CHECK (char_length(abs_user_id) BETWEEN 1 AND 100),
    username         TEXT NOT NULL CHECK (char_length(username) BETWEEN 1 AND 200),
    access_token     TEXT NOT NULL CHECK (char_length(access_token) <= 4096),
    refresh_token    TEXT NOT NULL CHECK (char_length(refresh_token) <= 4096),
    access_expires_at TIMESTAMPTZ NOT NULL,
    linked_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    synced_at        TIMESTAMPTZ,
    -- A short machine code for the last failed poll: auth_failed or unreachable. NULL when the
    -- last poll worked.
    last_error       TEXT CHECK (last_error IN ('auth_failed', 'unreachable'))
);

CREATE TABLE listening_daily (
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    minutes    INTEGER NOT NULL CHECK (minutes BETWEEN 0 AND 1440),
    synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);

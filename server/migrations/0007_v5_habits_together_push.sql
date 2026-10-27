-- v5: daily habits, cheers, the weekly couple challenge, shared rewards and push notifications.

-- Weekdays is a bitmask with bit 0 = Monday .. bit 6 = Sunday. Slots is a JSON array of
-- {"label": text, "time": "HH:MM" | null}; a slot's index is its position in the array.
-- A count habit has no slots and a daily target instead.
CREATE TABLE habits (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name       TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40 AND name = btrim(name)),
    icon       TEXT NOT NULL CHECK (char_length(icon) BETWEEN 1 AND 40),
    kind       TEXT NOT NULL CHECK (kind IN ('check', 'count')),
    weekdays   SMALLINT NOT NULL DEFAULT 127 CHECK (weekdays BETWEEN 1 AND 127),
    slots      JSONB NOT NULL DEFAULT '[]'::jsonb
               CHECK (jsonb_typeof(slots) = 'array' AND jsonb_array_length(slots) <= 8),
    target     INTEGER CHECK (target BETWEEN 1 AND 50),
    position   INTEGER NOT NULL DEFAULT 0,
    paused     BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CHECK ((kind = 'check' AND jsonb_array_length(slots) >= 1 AND target IS NULL)
        OR (kind = 'count' AND jsonb_array_length(slots) = 0 AND target IS NOT NULL))
);

CREATE INDEX habits_user_live ON habits (user_id, position, id) WHERE deleted_at IS NULL;

-- A check habit has one row per done slot (Count = 1). A count habit has one row at slot 0
-- holding the day's count; zero is stored as no row.
CREATE TABLE habit_marks (
    habit_id   BIGINT NOT NULL REFERENCES habits (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    slot       SMALLINT NOT NULL CHECK (slot BETWEEN 0 AND 7),
    count      INTEGER NOT NULL DEFAULT 1 CHECK (count BETWEEN 1 AND 1000),
    marked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (habit_id, local_date, slot)
);

-- LocalDate is the sender's local day, which is what makes "one per kind per day" mean the
-- same thing to the person tapping.
CREATE TABLE cheers (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_user  BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    to_user    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind       TEXT NOT NULL CHECK (kind IN ('clap', 'fire', 'flex', 'heart')),
    local_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (from_user, to_user, kind, local_date),
    CHECK (from_user <> to_user)
);

CREATE INDEX cheers_received ON cheers (to_user, created_at DESC);

-- One shared challenge per ISO week, created lazily with its target frozen.
CREATE TABLE challenges (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    week_start   DATE NOT NULL UNIQUE,
    kind         TEXT NOT NULL CHECK (kind IN ('steps', 'workouts', 'counted_days', 'reading')),
    title        TEXT NOT NULL,
    target       INTEGER NOT NULL CHECK (target > 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- The completion bonus of one person, on the local day it was earned. Scoring reads these as a
-- per-day bonus input, and the primary key makes the award happen once.
CREATE TABLE challenge_awards (
    challenge_id BIGINT NOT NULL REFERENCES challenges (id) ON DELETE CASCADE,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE NOT NULL,
    points       INTEGER NOT NULL CHECK (points > 0),
    PRIMARY KEY (challenge_id, user_id)
);

CREATE INDEX challenge_awards_day ON challenge_awards (user_id, local_date);

-- Baseline is the combined all-time points at the moment the reward started, so progress is
-- exact to the instant even though points are stored per day.
CREATE TABLE rewards (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40 AND name = btrim(name)),
    target      INTEGER NOT NULL CHECK (target BETWEEN 1 AND 100000),
    baseline    INTEGER NOT NULL CHECK (baseline >= 0),
    created_by  BIGINT REFERENCES users (id) ON DELETE SET NULL,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    reached_at  TIMESTAMPTZ,
    claimed_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX rewards_one_active ON rewards ((true)) WHERE reached_at IS NULL;

-- A token belongs to one install. A token that moves to another install (a re-pair) is
-- dropped from the old one first.
CREATE TABLE push_tokens (
    device_id  BIGINT PRIMARY KEY REFERENCES devices (id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token      TEXT NOT NULL UNIQUE CHECK (char_length(token) BETWEEN 32 AND 200),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX push_tokens_user ON push_tokens (user_id);

-- Marks an event as sent so a re-scored day cannot notify twice.
CREATE TABLE notice_log (
    kind       TEXT NOT NULL,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    sent_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (kind, user_id, local_date)
);

ALTER TABLE users
    ADD COLUMN notify_partner_done BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_cheers       BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_challenge    BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_reward       BOOLEAN NOT NULL DEFAULT true;

-- v7: streak freezes, repair, away mode and the shared streak, the general schedule, personal
-- challenge shares, the generic activity log, milestones and the health-soundness defaults.

-- What a finalized day did to the streak. Settled marks days whose outcome below is final;
-- every day finalized before this migration is settled, so the history stays as recorded.
ALTER TABLE day_scores
    ADD COLUMN frozen_reason TEXT CHECK (frozen_reason IN ('freeze', 'readiness', 'repair', 'cover')),
    ADD COLUMN away          BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN settled       BOOLEAN NOT NULL DEFAULT false;

UPDATE day_scores SET settled = true WHERE finalized_at IS NOT NULL;

ALTER TABLE users
    -- The first local date scored by the freeze rules. Earlier days keep the weekly rest rule
    -- they were finalized under. NULL means every day follows the freeze rules.
    ADD COLUMN streak_rules_from DATE,
    -- New people get 1.6 g/kg from their latest weight until they pick a protein target.
    ADD COLUMN protein_auto BOOLEAN NOT NULL DEFAULT false,
    -- Workdays is a bitmask with bit 0 = Monday; times are minutes after local midnight.
    ADD COLUMN workdays SMALLINT NOT NULL DEFAULT 31 CHECK (workdays BETWEEN 0 AND 127),
    ADD COLUMN workday_wake_min SMALLINT NOT NULL DEFAULT 420 CHECK (workday_wake_min BETWEEN 0 AND 1439),
    ADD COLUMN workday_bed_min  SMALLINT NOT NULL DEFAULT 1380 CHECK (workday_bed_min BETWEEN 0 AND 1439),
    ADD COLUMN dayoff_wake_min  SMALLINT NOT NULL DEFAULT 420 CHECK (dayoff_wake_min BETWEEN 0 AND 1439),
    ADD COLUMN dayoff_bed_min   SMALLINT NOT NULL DEFAULT 1380 CHECK (dayoff_bed_min BETWEEN 0 AND 1439),
    ADD COLUMN first_notification_offset_min SMALLINT NOT NULL DEFAULT 10
        CHECK (first_notification_offset_min BETWEEN 0 AND 120),
    ADD COLUMN notify_milestones BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_lookback   BOOLEAN NOT NULL DEFAULT true,
    ADD CONSTRAINT users_workday_times_differ CHECK (workday_wake_min <> workday_bed_min),
    ADD CONSTRAINT users_dayoff_times_differ CHECK (dayoff_wake_min <> dayoff_bed_min);

ALTER TABLE users ALTER COLUMN protein_auto SET DEFAULT true;

UPDATE users u SET streak_rules_from = GREATEST(u.joined_on, COALESCE(
    (SELECT max(s.local_date) + 1 FROM day_scores s WHERE s.user_id = u.id AND s.finalized_at IS NOT NULL),
    u.joined_on));

-- A span of days a person marked as away. Days settled while a span covered them keep the
-- away flag on day_scores, so removing a span later never rewrites the past.
CREATE TABLE away_spans (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    from_date  DATE NOT NULL,
    to_date    DATE NOT NULL,
    note       TEXT NOT NULL DEFAULT '' CHECK (char_length(note) <= 200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (to_date >= from_date AND to_date - from_date < 14)
);

CREATE INDEX away_spans_user ON away_spans (user_id, to_date);

-- A freeze one person spent on the other's missed day. The date is the covered person's local
-- date. A cover whose day ends up counted is deleted again, which refunds the freeze.
CREATE TABLE streak_covers (
    covered_user BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE NOT NULL,
    by_user      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (covered_user, local_date),
    CHECK (covered_user <> by_user)
);

CREATE INDEX streak_covers_by ON streak_covers (by_user, local_date);

-- Each person's own share of the weekly challenge. The challenge target is the sum of shares.
CREATE TABLE challenge_shares (
    challenge_id BIGINT NOT NULL REFERENCES challenges (id) ON DELETE CASCADE,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    target       INTEGER NOT NULL CHECK (target > 0),
    PRIMARY KEY (challenge_id, user_id)
);

-- Manual activity of any kind: a free name, minutes and how hard it was. It counts toward the
-- exercise quest. The old column checks are replaced because they list the type by name.
DO $$
DECLARE c TEXT;
BEGIN
    FOR c IN SELECT conname FROM pg_constraint WHERE conrelid = 'activity_logs'::regclass AND contype = 'c' LOOP
        EXECUTE format('ALTER TABLE activity_logs DROP CONSTRAINT %I', c);
    END LOOP;
END $$;

ALTER TABLE activity_logs
    ADD COLUMN name      TEXT CHECK (name IS NULL OR char_length(name) BETWEEN 1 AND 60),
    ADD COLUMN intensity TEXT CHECK (intensity IS NULL OR intensity IN ('easy', 'moderate', 'hard')),
    ADD CONSTRAINT activity_logs_type_known CHECK (type IN
        ('pushups', 'reading_minutes', 'reading_pages', 'yoga_minutes', 'other_minutes')),
    ADD CONSTRAINT activity_logs_quantity_bounds CHECK (quantity > 0 AND quantity <= CASE type
        WHEN 'pushups' THEN 500
        WHEN 'reading_pages' THEN 2000
        ELSE 1440
    END),
    ADD CONSTRAINT activity_logs_other_shape CHECK ((type = 'other_minutes') = (name IS NOT NULL AND intensity IS NOT NULL));

-- Proposals now also offer to switch a quest on and to move the protein target.
DO $$
DECLARE c TEXT;
BEGIN
    FOR c IN SELECT conname FROM pg_constraint
             WHERE conrelid = 'goal_proposals'::regclass AND contype = 'c'
               AND pg_get_constraintdef(oid) LIKE '%''steps''%' LOOP
        EXECUTE format('ALTER TABLE goal_proposals DROP CONSTRAINT %I', c);
    END LOOP;
END $$;

ALTER TABLE goal_proposals
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'target' CHECK (kind IN ('target', 'enable')),
    ADD CONSTRAINT goal_proposals_key_known CHECK (key IN ('steps', 'sleep', 'exercise', 'protein'));

-- Streak and first-time milestones, recorded once. A NULL user is a milestone of the couple.
CREATE TABLE milestones (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT REFERENCES users (id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN
        ('streak', 'shared_streak', 'first_10k_steps', 'first_all_quests', 'first_full_week')),
    value       INTEGER NOT NULL DEFAULT 0,
    achieved_on DATE NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((kind = 'shared_streak') = (user_id IS NULL))
);

CREATE UNIQUE INDEX milestones_once ON milestones (COALESCE(user_id, 0), kind, value);
CREATE INDEX milestones_recent ON milestones (achieved_on DESC);

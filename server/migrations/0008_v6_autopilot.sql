-- v6: nudge and recap preferences (behind pace and wind down start off to keep pushes few), the cached plan wording and the weekly goal proposals.

ALTER TABLE users
    ADD COLUMN notify_behind_pace   BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN notify_close_to_done BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_wind_down     BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN notify_morning_plan  BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_weekly_recap  BOOLEAN NOT NULL DEFAULT true;

-- One row per person and day claims the single Claude call for that day, so a failed or slow
-- call is never retried and cost stays bounded. Text stays NULL until the call succeeds.
-- Facts_key fingerprints which quests were done and open when the text was written.
CREATE TABLE plan_polish (
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE NOT NULL,
    facts_key    TEXT NOT NULL,
    text         TEXT CHECK (text IS NULL OR char_length(text) BETWEEN 1 AND 800),
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);

-- A proposal is frozen when first shown and decided at most once per week, which is what
-- keeps a dismissed proposal from coming back until next Monday.
CREATE TABLE goal_proposals (
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    key        TEXT NOT NULL CHECK (key IN ('steps', 'sleep')),
    current    INTEGER NOT NULL CHECK (current > 0),
    proposed   INTEGER NOT NULL CHECK (proposed > 0),
    reason     TEXT NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 300),
    state      TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'accepted', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, week_start, key)
);

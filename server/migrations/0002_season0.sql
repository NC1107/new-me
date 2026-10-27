CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 0001 seeds Season 0 from current_date, which is past its fixed end once a fresh database is
-- migrated after 2026-12-31. Clamp so the CHECK below can still be added then.
UPDATE seasons SET starts_on = ends_on WHERE ends_on < starts_on;

ALTER TABLE seasons
    ADD CONSTRAINT seasons_ends_after_start CHECK (ends_on IS NULL OR ends_on >= starts_on),
    ADD CONSTRAINT seasons_no_overlap EXCLUDE USING gist (
        daterange(starts_on, COALESCE(ends_on, 'infinity'::date), '[]') WITH &&
    );

-- One bounds table for quest targets, shared by templates and day snapshots so the two cannot
-- drift. Reading is the only quest with a second (pages) target.
CREATE FUNCTION quest_target_ok(key TEXT, target INTEGER, target_alt INTEGER) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(CASE key
        WHEN 'steps'        THEN target BETWEEN 1 AND 100000 AND target_alt IS NULL
        WHEN 'pushups'      THEN target BETWEEN 1 AND 500    AND target_alt IS NULL
        WHEN 'reading'      THEN target BETWEEN 1 AND 1440   AND target_alt BETWEEN 1 AND 2000
        WHEN 'meals_logged' THEN target BETWEEN 1 AND 20     AND target_alt IS NULL
        WHEN 'protein'      THEN target BETWEEN 1 AND 1000   AND target_alt IS NULL
        WHEN 'yoga'         THEN target BETWEEN 1 AND 1440   AND target_alt IS NULL
        ELSE false
    END, false)
$$;

CREATE TABLE users (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40 AND name = btrim(name)),
    color          TEXT NOT NULL CHECK (char_length(color) BETWEEN 1 AND 20),
    timezone       TEXT NOT NULL DEFAULT 'America/New_York',
    is_admin       BOOLEAN NOT NULL DEFAULT false,
    kcal_target    INTEGER CHECK (kcal_target BETWEEN 1 AND 10000),
    protein_target INTEGER CHECK (protein_target BETWEEN 1 AND 1000),
    carbs_target   INTEGER CHECK (carbs_target BETWEEN 1 AND 1000),
    fat_target     INTEGER CHECK (fat_target BETWEEN 1 AND 1000),
    joined_on      DATE NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);

CREATE UNIQUE INDEX users_name_live ON users (lower(name)) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_color_live ON users (color) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_single_admin ON users (is_admin) WHERE is_admin AND deleted_at IS NULL;

CREATE TABLE devices (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash   TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX devices_user ON devices (user_id);

CREATE TABLE invites (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code_hash  TEXT NOT NULL UNIQUE,
    created_by BIGINT REFERENCES users (id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    attempts   INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0)
);

CREATE TABLE quest_templates (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key        TEXT NOT NULL CHECK (key IN ('steps', 'pushups', 'reading', 'meals_logged', 'protein', 'yoga')),
    target     INTEGER NOT NULL,
    unit       TEXT NOT NULL,
    target_alt INTEGER,
    unit_alt   TEXT,
    points     INTEGER NOT NULL CHECK (points > 0 AND points % 5 = 0),
    enabled    BOOLEAN NOT NULL DEFAULT true,
    position   INTEGER NOT NULL DEFAULT 0,
    UNIQUE (user_id, key),
    CHECK (quest_target_ok(key, target, target_alt)),
    CHECK ((target_alt IS NULL) = (unit_alt IS NULL))
);

CREATE TABLE day_quests (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    key        TEXT NOT NULL CHECK (key IN ('steps', 'pushups', 'reading', 'meals_logged', 'protein', 'yoga')),
    target     INTEGER NOT NULL,
    unit       TEXT NOT NULL,
    target_alt INTEGER,
    unit_alt   TEXT,
    points     INTEGER NOT NULL CHECK (points > 0 AND points % 5 = 0),
    position   INTEGER NOT NULL DEFAULT 0,
    UNIQUE (user_id, local_date, key),
    CHECK (quest_target_ok(key, target, target_alt)),
    CHECK ((target_alt IS NULL) = (unit_alt IS NULL))
);

-- Activity and meal ids share one sequence so DELETE /logs/{id} needs no kind.
CREATE SEQUENCE log_id_seq;

CREATE TABLE activity_logs (
    id           BIGINT PRIMARY KEY DEFAULT nextval('log_id_seq'),
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE NOT NULL,
    type         TEXT NOT NULL CHECK (type IN ('pushups', 'reading_minutes', 'reading_pages', 'yoga_minutes')),
    quantity     INTEGER NOT NULL,
    client_op_id UUID NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ,
    UNIQUE (user_id, client_op_id),
    CHECK (quantity > 0 AND quantity <= CASE type
        WHEN 'pushups' THEN 500
        WHEN 'reading_pages' THEN 2000
        ELSE 1440
    END)
);

CREATE INDEX activity_logs_day ON activity_logs (user_id, local_date) WHERE deleted_at IS NULL;

CREATE TABLE meal_logs (
    id           BIGINT PRIMARY KEY DEFAULT nextval('log_id_seq'),
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE NOT NULL,
    name         TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
    kcal         INTEGER NOT NULL CHECK (kcal > 0 AND kcal <= 10000),
    protein_g    NUMERIC(6, 1) NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
    carbs_g      NUMERIC(6, 1) NOT NULL DEFAULT 0 CHECK (carbs_g >= 0),
    fat_g        NUMERIC(6, 1) NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
    fiber_g      NUMERIC(6, 1) NOT NULL DEFAULT 0 CHECK (fiber_g >= 0),
    client_op_id UUID NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ,
    UNIQUE (user_id, client_op_id)
);

CREATE INDEX meal_logs_day ON meal_logs (user_id, local_date) WHERE deleted_at IS NULL;
CREATE INDEX meal_logs_recent ON meal_logs (logged_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE health_daily (
    user_id     BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date  DATE NOT NULL,
    metric      TEXT NOT NULL CHECK (metric IN ('steps', 'active_energy')),
    value       DOUBLE PRECISION NOT NULL,
    source      TEXT NOT NULL DEFAULT 'healthkit' CHECK (char_length(source) BETWEEN 1 AND 32),
    measured_at TIMESTAMPTZ NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date, metric),
    -- NaN sorts above every number in Postgres, so it fails these upper bounds too.
    CHECK (CASE metric
        WHEN 'steps' THEN value >= 0 AND value <= 200000
        ELSE value >= 0 AND value <= 20000
    END)
);

CREATE TABLE day_scores (
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE NOT NULL,
    base_points  INTEGER NOT NULL CHECK (base_points >= 0),
    bonus_points INTEGER NOT NULL CHECK (bonus_points >= 0),
    max_base     INTEGER NOT NULL CHECK (max_base >= 0),
    percent      INTEGER NOT NULL CHECK (percent BETWEEN 0 AND 100),
    counted      BOOLEAN NOT NULL,
    detail       JSONB NOT NULL DEFAULT '[]',
    finalized_at TIMESTAMPTZ,
    computed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date),
    -- Mirrors score.CountedPercent so a hand-edited row cannot disagree with the rule.
    CHECK (counted = (max_base > 0 AND base_points * 100 >= 70 * max_base))
);

CREATE INDEX day_scores_recent ON day_scores (user_id, local_date DESC);

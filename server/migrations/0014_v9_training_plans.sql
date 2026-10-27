-- v9 training, part 2: training profiles, plans and the sessions they schedule.

-- What a plan is built for. One row per person, created on first save.
CREATE TABLE training_profiles (
    user_id         BIGINT      PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    equipment       TEXT[]      NOT NULL DEFAULT '{}',
    dumbbell_max_kg NUMERIC(5, 1) CHECK (dumbbell_max_kg > 0 AND dumbbell_max_kg <= 200),
    days_per_week   SMALLINT    NOT NULL CHECK (days_per_week BETWEEN 2 AND 6),
    session_minutes SMALLINT    NOT NULL CHECK (session_minutes BETWEEN 20 AND 90),
    experience      TEXT        NOT NULL CHECK (experience IN ('new', 'some', 'experienced')),
    focus           TEXT        NOT NULL DEFAULT '' CHECK (char_length(focus) <= 300),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (equipment <@ ARRAY['pullup_bar', 'dumbbells', 'barbell', 'bench', 'bands', 'dip_bars',
                              'hangboard', 'gym']::text[])
);

-- A validated plan: a weekly template (days) repeated for the block. At most one active plan
-- per person; ending a plan keeps it for history.
CREATE TABLE training_plans (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    starts_on  DATE        NOT NULL,
    weeks      SMALLINT    NOT NULL CHECK (weeks BETWEEN 4 AND 6),
    days       JSONB       NOT NULL,
    notes      TEXT        NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at   TIMESTAMPTZ
);

CREATE UNIQUE INDEX training_plans_one_active ON training_plans (user_id) WHERE ended_at IS NULL;

-- One scheduled session: the plan day due on a date, created when the person first looks at
-- that date's training. Completing it completes the day's strength quest.
CREATE TABLE training_sessions (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    plan_id      BIGINT      NOT NULL REFERENCES training_plans (id) ON DELETE CASCADE,
    local_date   DATE        NOT NULL,
    day_index    SMALLINT    NOT NULL CHECK (day_index >= 0),
    completed_at TIMESTAMPTZ,
    UNIQUE (user_id, local_date)
);

ALTER TABLE exercise_sets
    ADD CONSTRAINT exercise_sets_session_fk FOREIGN KEY (session_id) REFERENCES training_sessions (id) ON DELETE SET NULL;

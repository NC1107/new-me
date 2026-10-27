-- v9 training, part 1: the exercise catalog, custom exercises, sets and max tests.

-- One row per exercise. Catalog rows have no owner and a stable key; a person's custom
-- exercises have an owner and a generated key. Muscles and equipment are small fixed vocabularies
-- checked here so plans and progress can group by them.
CREATE TABLE exercises (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    key               TEXT        NOT NULL UNIQUE CHECK (key ~ '^[a-z0-9_]{2,60}$'),
    -- No foreign key: the catalog is migration data that must survive truncating users, and
    -- people are soft deleted, so custom rows never dangle in practice.
    user_id           BIGINT,
    name              TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    primary_muscles   TEXT[]      NOT NULL CHECK (cardinality(primary_muscles) BETWEEN 1 AND 4),
    secondary_muscles TEXT[]      NOT NULL DEFAULT '{}',
    measure           TEXT        NOT NULL CHECK (measure IN ('reps', 'seconds')),
    load              TEXT        NOT NULL CHECK (load IN ('bodyweight', 'external')),
    equipment         TEXT[]      NOT NULL DEFAULT '{}',
    easier_key        TEXT,
    harder_key        TEXT,
    position          INTEGER     NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    CHECK (primary_muscles <@ ARRAY['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
                                    'quads', 'hamstrings', 'glutes', 'calves', 'core']::text[]),
    CHECK (secondary_muscles <@ ARRAY['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
                                      'quads', 'hamstrings', 'glutes', 'calves', 'core']::text[]),
    CHECK (equipment <@ ARRAY['pullup_bar', 'dumbbells', 'barbell', 'bench', 'bands', 'dip_bars',
                              'hangboard', 'gym']::text[])
);

CREATE INDEX exercises_owner ON exercises (user_id) WHERE deleted_at IS NULL;

INSERT INTO exercises (key, name, primary_muscles, secondary_muscles, measure, load, equipment, easier_key, harder_key, position) VALUES
    ('incline_push_up', 'Incline push-up', '{chest}', '{triceps,shoulders}', 'reps', 'bodyweight', '{}', NULL, 'push_up', 10),
    ('push_up', 'Push-up', '{chest}', '{triceps,shoulders,core}', 'reps', 'bodyweight', '{}', 'incline_push_up', 'decline_push_up', 11),
    ('decline_push_up', 'Decline push-up', '{chest,shoulders}', '{triceps,core}', 'reps', 'bodyweight', '{}', 'push_up', NULL, 12),
    ('band_pull_up', 'Band-assisted pull-up', '{back}', '{biceps}', 'reps', 'bodyweight', '{pullup_bar,bands}', NULL, 'negative_pull_up', 20),
    ('negative_pull_up', 'Negative pull-up', '{back}', '{biceps,forearms}', 'reps', 'bodyweight', '{pullup_bar}', 'band_pull_up', 'pull_up', 21),
    ('pull_up', 'Pull-up', '{back}', '{biceps,forearms}', 'reps', 'bodyweight', '{pullup_bar}', 'negative_pull_up', NULL, 22),
    ('chin_up', 'Chin-up', '{back,biceps}', '{forearms}', 'reps', 'bodyweight', '{pullup_bar}', 'negative_pull_up', NULL, 23),
    ('inverted_row', 'Inverted row', '{back}', '{biceps}', 'reps', 'bodyweight', '{}', NULL, 'pull_up', 24),
    ('dead_hang', 'Dead hang', '{forearms}', '{back,shoulders}', 'seconds', 'bodyweight', '{pullup_bar}', NULL, NULL, 25),
    ('bench_dip', 'Bench dip', '{triceps}', '{chest,shoulders}', 'reps', 'bodyweight', '{bench}', NULL, 'dip', 30),
    ('dip', 'Dip', '{triceps,chest}', '{shoulders}', 'reps', 'bodyweight', '{dip_bars}', 'bench_dip', NULL, 31),
    ('air_squat', 'Air squat', '{quads}', '{glutes}', 'reps', 'bodyweight', '{}', NULL, 'split_squat', 40),
    ('split_squat', 'Split squat', '{quads,glutes}', '{hamstrings}', 'reps', 'bodyweight', '{}', 'air_squat', 'bulgarian_split_squat', 41),
    ('bulgarian_split_squat', 'Bulgarian split squat', '{quads,glutes}', '{hamstrings}', 'reps', 'bodyweight', '{bench}', 'split_squat', NULL, 42),
    ('lunge', 'Lunge', '{quads,glutes}', '{hamstrings}', 'reps', 'bodyweight', '{}', NULL, NULL, 43),
    ('step_up', 'Step-up', '{quads,glutes}', '{}', 'reps', 'bodyweight', '{bench}', NULL, NULL, 44),
    ('glute_bridge', 'Glute bridge', '{glutes}', '{hamstrings}', 'reps', 'bodyweight', '{}', NULL, 'single_leg_glute_bridge', 45),
    ('single_leg_glute_bridge', 'Single-leg glute bridge', '{glutes}', '{hamstrings,core}', 'reps', 'bodyweight', '{}', 'glute_bridge', NULL, 46),
    ('good_morning', 'Good morning', '{hamstrings}', '{glutes,back}', 'reps', 'bodyweight', '{}', NULL, NULL, 47),
    ('calf_raise', 'Calf raise', '{calves}', '{}', 'reps', 'bodyweight', '{}', NULL, NULL, 48),
    ('plank', 'Plank', '{core}', '{shoulders}', 'seconds', 'bodyweight', '{}', NULL, NULL, 50),
    ('side_plank', 'Side plank', '{core}', '{shoulders}', 'seconds', 'bodyweight', '{}', NULL, NULL, 51),
    ('hollow_hold', 'Hollow hold', '{core}', '{}', 'seconds', 'bodyweight', '{}', NULL, NULL, 52),
    ('burpee', 'Burpee', '{quads,chest}', '{core,shoulders}', 'reps', 'bodyweight', '{}', NULL, NULL, 53),
    ('goblet_squat', 'Goblet squat', '{quads,glutes}', '{core}', 'reps', 'external', '{dumbbells}', NULL, NULL, 60),
    ('db_romanian_deadlift', 'Dumbbell Romanian deadlift', '{hamstrings,glutes}', '{back}', 'reps', 'external', '{dumbbells}', NULL, NULL, 61),
    ('db_bench_press', 'Dumbbell bench press', '{chest}', '{triceps,shoulders}', 'reps', 'external', '{dumbbells,bench}', NULL, NULL, 62),
    ('db_row', 'Dumbbell row', '{back}', '{biceps}', 'reps', 'external', '{dumbbells}', NULL, NULL, 63),
    ('db_overhead_press', 'Dumbbell overhead press', '{shoulders}', '{triceps}', 'reps', 'external', '{dumbbells}', NULL, NULL, 64),
    ('lateral_raise', 'Lateral raise', '{shoulders}', '{}', 'reps', 'external', '{dumbbells}', NULL, NULL, 65),
    ('biceps_curl', 'Biceps curl', '{biceps}', '{forearms}', 'reps', 'external', '{dumbbells}', NULL, NULL, 66),
    ('triceps_extension', 'Triceps extension', '{triceps}', '{}', 'reps', 'external', '{dumbbells}', NULL, NULL, 67),
    ('back_squat', 'Barbell back squat', '{quads,glutes}', '{hamstrings,core}', 'reps', 'external', '{barbell}', NULL, NULL, 70),
    ('deadlift', 'Barbell deadlift', '{hamstrings,glutes,back}', '{quads,forearms}', 'reps', 'external', '{barbell}', NULL, NULL, 71),
    ('bench_press', 'Barbell bench press', '{chest}', '{triceps,shoulders}', 'reps', 'external', '{barbell,bench}', NULL, NULL, 72),
    ('overhead_press', 'Barbell overhead press', '{shoulders}', '{triceps,core}', 'reps', 'external', '{barbell}', NULL, NULL, 73),
    ('hangboard_hang', 'Hangboard hang', '{forearms}', '{back}', 'seconds', 'bodyweight', '{hangboard}', NULL, NULL, 80);

-- One logged set. reps or seconds per the exercise's measure; load only for external loads.
-- Logged once per client op id like activity logs, and soft deleted.
CREATE TABLE exercise_sets (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date   DATE        NOT NULL,
    exercise_id  BIGINT      NOT NULL REFERENCES exercises (id),
    reps         INTEGER     CHECK (reps BETWEEN 1 AND 500),
    seconds      INTEGER     CHECK (seconds BETWEEN 1 AND 3600),
    load_kg      NUMERIC(6, 2) CHECK (load_kg > 0 AND load_kg <= 1000),
    rir          SMALLINT    CHECK (rir BETWEEN 0 AND 10),
    session_id   BIGINT,
    client_op_id UUID        NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ,
    UNIQUE (user_id, client_op_id),
    CHECK ((reps IS NULL) <> (seconds IS NULL))
);

CREATE INDEX exercise_sets_day ON exercise_sets (user_id, local_date) WHERE deleted_at IS NULL;
CREATE INDEX exercise_sets_exercise ON exercise_sets (user_id, exercise_id, local_date) WHERE deleted_at IS NULL;

-- A max test for any exercise: one set to near failure, at most one per exercise and day.
-- Push-ups keep their own v8 table, which the targets read.
CREATE TABLE exercise_max_tests (
    user_id     BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    exercise_id BIGINT      NOT NULL REFERENCES exercises (id),
    local_date  DATE        NOT NULL,
    reps        INTEGER     CHECK (reps BETWEEN 1 AND 1000),
    seconds     INTEGER     CHECK (seconds BETWEEN 1 AND 3600),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, exercise_id, local_date),
    CHECK ((reps IS NULL) <> (seconds IS NULL))
);

-- Workouts and sleep nights from Apple Health, and the birth year that picks the step band.

CREATE TABLE workouts (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- The HealthKit sample UUID, so re-sending the same workout updates it in place.
    health_id    TEXT NOT NULL CHECK (char_length(health_id) BETWEEN 1 AND 100),
    type         TEXT NOT NULL CHECK (type IN (
        'walking', 'running', 'cycling', 'strength', 'hiit', 'yoga', 'swimming', 'hiking',
        'dance', 'climbing', 'other')),
    local_date   DATE NOT NULL,
    started_at   TIMESTAMPTZ NOT NULL,
    ended_at     TIMESTAMPTZ NOT NULL,
    duration_min NUMERIC(6,1) NOT NULL CHECK (duration_min > 0 AND duration_min <= 1440),
    kcal         NUMERIC(7,1) CHECK (kcal BETWEEN 0 AND 20000),
    distance_m   NUMERIC(9,1) CHECK (distance_m BETWEEN 0 AND 1000000),
    avg_hr       NUMERIC(4,1) CHECK (avg_hr BETWEEN 20 AND 250),
    source       TEXT NOT NULL CHECK (char_length(source) BETWEEN 1 AND 32),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, health_id),
    CHECK (ended_at > started_at)
);

CREATE INDEX workouts_user_day ON workouts (user_id, local_date DESC);

-- One record per night, keyed by the morning the night ends.
CREATE TABLE sleep_nights (
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    bed_at     TIMESTAMPTZ NOT NULL,
    wake_at    TIMESTAMPTZ NOT NULL,
    asleep_min INTEGER NOT NULL CHECK (asleep_min BETWEEN 0 AND 1440),
    deep_min   INTEGER NOT NULL CHECK (deep_min BETWEEN 0 AND 1440),
    rem_min    INTEGER NOT NULL CHECK (rem_min BETWEEN 0 AND 1440),
    core_min   INTEGER NOT NULL CHECK (core_min BETWEEN 0 AND 1440),
    awake_min  INTEGER NOT NULL CHECK (awake_min BETWEEN 0 AND 1440),
    source     TEXT NOT NULL CHECK (char_length(source) BETWEEN 1 AND 32),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date),
    CHECK (wake_at > bed_at AND wake_at - bed_at <= interval '24 hours')
);

-- The current year is enforced by the API, since a CHECK cannot depend on the clock.
ALTER TABLE users
    ADD COLUMN birth_year INTEGER CHECK (birth_year BETWEEN 1900 AND 2100);

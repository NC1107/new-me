-- v18: shared household habits (chores). Both people see the same list, either marks one done,
-- and the person who did it earns the gems as a bonus that never touches the daily percent.

CREATE TABLE shared_habits (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40 AND name = btrim(name)),
    icon          TEXT NOT NULL,
    -- weekly is every 7 days and every_n uses every_days; both count from the last time it was
    -- done, or from the day it was created while it never was.
    schedule_kind TEXT NOT NULL CHECK (schedule_kind IN ('daily', 'weekdays', 'weekly', 'every_n')),
    weekdays      INTEGER NOT NULL DEFAULT 127 CHECK (weekdays BETWEEN 1 AND 127),
    every_days    INTEGER CHECK (every_days BETWEEN 2 AND 365),
    CHECK ((schedule_kind = 'every_n') = (every_days IS NOT NULL)),
    -- start_on is the created day in the creator's zone, where a chore that was never done is due.
    start_on      DATE NOT NULL,
    created_by    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);

CREATE INDEX shared_habits_live ON shared_habits (id) WHERE deleted_at IS NULL;

-- One row per time a chore was done. local_date is the doer's own day, which is the day the
-- gems count on; an undo deletes the row so the gems leave with it.
CREATE TABLE shared_habit_marks (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shared_habit_id BIGINT NOT NULL REFERENCES shared_habits (id) ON DELETE CASCADE,
    user_id         BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date      DATE NOT NULL,
    done_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    points          INTEGER NOT NULL CHECK (points >= 0)
);

CREATE INDEX shared_habit_marks_habit ON shared_habit_marks (shared_habit_id, done_at DESC);
CREATE INDEX shared_habit_marks_day ON shared_habit_marks (user_id, local_date);

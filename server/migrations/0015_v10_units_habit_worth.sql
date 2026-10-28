-- v10: the units a person reads, and each habit's worth toward the daily goal.

ALTER TABLE users
    ADD COLUMN units TEXT NOT NULL DEFAULT 'metric' CHECK (units IN ('metric', 'imperial'));

-- Points a due habit adds to the day's possible points: 0 tracks only, 10, 25 or 50 count.
-- Existing habits start at the middle worth.
ALTER TABLE habits
    ADD COLUMN points SMALLINT NOT NULL DEFAULT 25 CHECK (points IN (0, 10, 25, 50));

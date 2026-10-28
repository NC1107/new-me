-- v11: a habit is paid by the minute and the partner approves the gems.

-- Minutes the habit takes, null for one that is only tracked (and for habits made before v11).
-- A proposal is pending while proposed_at is set; proposed_minutes is null when it proposes
-- only tracking.
ALTER TABLE habits
    ADD COLUMN minutes          SMALLINT CHECK (minutes BETWEEN 1 AND 30),
    ADD COLUMN proposed_points  SMALLINT CHECK (proposed_points BETWEEN 0 AND 100),
    ADD COLUMN proposed_minutes SMALLINT CHECK (proposed_minutes BETWEEN 1 AND 30),
    ADD COLUMN proposed_at      TIMESTAMPTZ,
    ADD CONSTRAINT habits_proposal_whole CHECK ((proposed_at IS NULL) = (proposed_points IS NULL));

-- Gems are 3 a minute capped at 100, so the old 0/10/25/50 set no longer bounds them.
ALTER TABLE habits DROP CONSTRAINT habits_points_check;
ALTER TABLE habits ADD CONSTRAINT habits_points_check CHECK (points BETWEEN 0 AND 100);

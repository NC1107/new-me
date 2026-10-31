-- v19: a chore's worth is agreed by both people, and a completion records who did it.

-- worth is the agreed gems, 25 until the two people settle on another number. A proposed worth
-- waits for the person who did not propose it; the proposer can replace it, the other accepts it
-- or counters with a number of their own.
ALTER TABLE shared_habits
    ADD COLUMN worth          INTEGER NOT NULL DEFAULT 25 CHECK (worth BETWEEN 1 AND 100),
    ADD COLUMN proposed_worth INTEGER CHECK (proposed_worth BETWEEN 1 AND 100),
    ADD COLUMN proposed_by    BIGINT REFERENCES users (id) ON DELETE SET NULL,
    ADD COLUMN proposed_at    TIMESTAMPTZ;

-- user_id and points stay the person who marked it and what they earned. When the other person
-- did it too, or instead, their share sits beside it, on their own local day, so each person's
-- bonus for a day is a sum over both columns.
ALTER TABLE shared_habit_marks
    ADD COLUMN done_by         TEXT NOT NULL DEFAULT 'self' CHECK (done_by IN ('self', 'partner', 'together')),
    ADD COLUMN other_user_id   BIGINT REFERENCES users (id) ON DELETE CASCADE,
    ADD COLUMN other_local_date DATE,
    ADD COLUMN other_points    INTEGER NOT NULL DEFAULT 0 CHECK (other_points >= 0),
    ADD CONSTRAINT shared_habit_marks_other CHECK (
        (done_by = 'self') = (other_user_id IS NULL) AND (other_user_id IS NULL) = (other_local_date IS NULL));

CREATE INDEX shared_habit_marks_other_day ON shared_habit_marks (other_user_id, other_local_date)
    WHERE other_user_id IS NOT NULL;

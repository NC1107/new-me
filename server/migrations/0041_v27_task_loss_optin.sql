-- v27: a missed task costs nothing unless its assignee chose to put the gems on the line, and a
-- loss never takes more than they held at the deadline. lose_if_missed is that choice and lost is
-- what the miss actually took; the ledger now reads lost instead of the whole stake.
ALTER TABLE tasks
    ADD COLUMN lose_if_missed BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN lost INTEGER NOT NULL DEFAULT 0 CHECK (lost >= 0);

-- Tasks agreed before this change were agreed with the stake at risk, so they keep that promise.
UPDATE tasks SET lose_if_missed = true;
UPDATE tasks SET lost = stake WHERE status = 'missed';

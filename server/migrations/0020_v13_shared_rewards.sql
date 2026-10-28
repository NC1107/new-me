-- v13: rewards become a shared wishlist priced in gems.
--
-- target is now the price. The pair's bank is every gem both have earned minus the spent of
-- claimed rewards, so baseline no longer means anything for new rows. proposed_by is who made
-- the latest proposal (a new reward or a price change), and the other person answers it.
ALTER TABLE rewards
    ADD COLUMN status      TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'declined', 'approved', 'claimed', 'cancelled')),
    ADD COLUMN proposed_by BIGINT REFERENCES users (id) ON DELETE SET NULL,
    ADD COLUMN is_focus    BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN spent       INTEGER NOT NULL DEFAULT 0 CHECK (spent >= 0),
    ADD COLUMN updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD CONSTRAINT rewards_focus_is_approved CHECK (NOT is_focus OR status = 'approved');

ALTER TABLE rewards ALTER COLUMN baseline SET DEFAULT 0;

DROP INDEX rewards_one_active;

-- Existing rewards keep working: a claimed one is history that spent its target, every other
-- one is approved. The open reward (or else the newest reached one nobody enjoyed yet) is the
-- focus, which is what /board showed before.
UPDATE rewards SET proposed_by = created_by;
UPDATE rewards SET status = 'claimed', spent = target WHERE claimed_at IS NOT NULL;
UPDATE rewards SET status = 'approved' WHERE claimed_at IS NULL;
UPDATE rewards SET is_focus = true
WHERE id = (
    SELECT id FROM rewards WHERE status = 'approved'
    ORDER BY (reached_at IS NULL) DESC, reached_at DESC, id DESC LIMIT 1
);

CREATE UNIQUE INDEX rewards_one_focus ON rewards ((true)) WHERE is_focus;
CREATE INDEX rewards_open ON rewards (status, id) WHERE status IN ('pending', 'declined', 'approved');

-- v13 held pushes: a push with no retry path (cheer, challenge complete, reward ready, proposals,
-- cover) that lands in quiet hours or on an away day waits here until the person's next allowed
-- time, instead of being dropped. The scheduler delivers due rows, collapses duplicates of the same
-- kind and subject, and drops what is older than a day. Claim-based pushes never come here.
CREATE TABLE held_pushes (
    id            BIGSERIAL   PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind          TEXT        NOT NULL,
    title         TEXT        NOT NULL,
    body          TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL,
    deliver_after TIMESTAMPTZ NOT NULL,
    delivered_at  TIMESTAMPTZ
);

CREATE INDEX held_pushes_due ON held_pushes (deliver_after) WHERE delivered_at IS NULL;

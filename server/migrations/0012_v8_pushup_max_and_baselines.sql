-- A push-up max test: one set to near failure. The newest test sizes the daily push-up target.
-- One test a day; testing again the same day replaces it.
CREATE TABLE pushup_max_tests (
    user_id    BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE        NOT NULL,
    reps       INTEGER     NOT NULL CHECK (reps BETWEEN 1 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);

-- The formula value of a target the last time the person applied, accepted or dismissed it (or
-- first saw it), with the inputs it was computed from. A Monday proposal compares the formula
-- value now with this baseline, so it is only ever made because an input moved.
CREATE TABLE target_baselines (
    user_id  BIGINT           NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key      TEXT             NOT NULL CHECK (key IN ('calories', 'protein')),
    value    DOUBLE PRECISION NOT NULL,
    inputs   JSONB            NOT NULL DEFAULT '{}',
    set_on   DATE             NOT NULL,
    PRIMARY KEY (user_id, key)
);

-- Calorie proposals join the Monday list, and a formula-change reason carries the formula
-- sentence, which is longer than the earlier reasons.
ALTER TABLE goal_proposals
    DROP CONSTRAINT goal_proposals_key_known,
    DROP CONSTRAINT goal_proposals_reason_check;

ALTER TABLE goal_proposals
    ADD CONSTRAINT goal_proposals_key_known CHECK (key IN ('steps', 'sleep', 'exercise', 'protein', 'calories')),
    ADD CONSTRAINT goal_proposals_reason_check CHECK (char_length(reason) BETWEEN 1 AND 600);

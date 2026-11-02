-- v21: what the coach knows about a person, and the target changes it proposes in chat.
-- Both are private to the person; nothing here is ever read for the partner.

CREATE TABLE coach_facts (
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    category   TEXT NOT NULL CHECK (category IN ('injury', 'schedule', 'preference', 'equipment', 'diet', 'other')),
    text       TEXT NOT NULL CHECK (char_length(text) BETWEEN 1 AND 200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX coach_facts_user_idx ON coach_facts (user_id, id);

-- A change the coach proposed. after_state is what Apply writes and before_state what Undo
-- restores; before_state is captured at Apply from the live values, so Undo is exact.
CREATE TABLE coach_proposals (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind         TEXT NOT NULL CHECK (kind IN ('quest_target', 'food_target', 'training_profile', 'body', 'weight_goal', 'goal_proposal')),
    summary      TEXT NOT NULL,
    reason       TEXT NOT NULL DEFAULT '',
    after_state  JSONB NOT NULL,
    before_state JSONB,
    status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'applied', 'dismissed', 'undone')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ NOT NULL,
    decided_at   TIMESTAMPTZ
);

CREATE INDEX coach_proposals_user_idx ON coach_proposals (user_id, id DESC);

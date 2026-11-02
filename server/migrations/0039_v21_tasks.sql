-- v21: agreed tasks. A task is a chore with a stake in gems. Its assignee wins the stake by
-- finishing before the deadline and loses it by missing it. Both people agree before it is live.
-- Won and lost stakes are a ledger of their own (the done and missed rows here), never day points.
CREATE TABLE tasks (
    id          BIGSERIAL PRIMARY KEY,
    title       TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 60),
    creator_id  BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    assignee_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    stake       INTEGER NOT NULL CHECK (stake BETWEEN 1 AND 100000),
    -- The last day it counts, on the assignee's calendar.
    deadline    DATE NOT NULL,
    status      TEXT NOT NULL CHECK (status IN ('proposed', 'declined', 'agreed', 'done', 'missed', 'withdrawn')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    agreed_at   TIMESTAMPTZ,
    -- Set once, when the task becomes done or missed; the gems move at that moment and no other.
    settled_at  TIMESTAMPTZ,
    CONSTRAINT tasks_settled_when_final CHECK ((status IN ('done', 'missed')) = (settled_at IS NOT NULL))
);

CREATE INDEX tasks_open ON tasks (deadline) WHERE status IN ('proposed', 'declined', 'agreed');
CREATE INDEX tasks_ledger ON tasks (assignee_id) WHERE status IN ('done', 'missed');
CREATE INDEX tasks_history ON tasks (settled_at DESC, id DESC) WHERE settled_at IS NOT NULL;

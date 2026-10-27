CREATE TABLE server_config (
    id          SMALLINT PRIMARY KEY CHECK (id = 1),
    name        TEXT NOT NULL DEFAULT 'New Me',
    initialized BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO server_config (id) VALUES (1);

CREATE TABLE seasons (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name      TEXT NOT NULL,
    starts_on DATE NOT NULL,
    ends_on   DATE
);

INSERT INTO seasons (name, starts_on, ends_on) VALUES
    ('Season 0', current_date, '2026-12-31'),
    ('Season 1', '2027-01-01', NULL);

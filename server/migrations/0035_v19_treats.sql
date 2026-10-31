-- v19: personal treats. A treat is a reward with an owner (owner_id set) that its owner redeems
-- again and again from their own gems, so it is never the focus and never claimed. It is priced
-- through the same proposal flow as a shared reward.
ALTER TABLE rewards
    ADD COLUMN owner_id BIGINT REFERENCES users (id) ON DELETE CASCADE,
    ADD CONSTRAINT rewards_treat_never_focus CHECK (owner_id IS NULL OR NOT is_focus),
    ADD CONSTRAINT rewards_treat_never_claimed CHECK (owner_id IS NULL OR status <> 'claimed');

CREATE INDEX rewards_owner ON rewards (owner_id) WHERE owner_id IS NOT NULL;

-- Every redemption keeps the name and price it was bought at, so history survives a later price
-- change or a removed treat. request_id makes a double tap a single redemption.
CREATE TABLE treat_redemptions (
    id         BIGSERIAL PRIMARY KEY,
    treat_id   BIGINT REFERENCES rewards (id) ON DELETE SET NULL,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    price      INTEGER NOT NULL CHECK (price > 0),
    request_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, request_id)
);
CREATE INDEX treat_redemptions_recent ON treat_redemptions (created_at DESC, id DESC);

-- Who paid how much of each claimed shared reward, so a person's own balance is exact. The
-- amounts of one claim add up to its price.
CREATE TABLE reward_payments (
    reward_id BIGINT NOT NULL REFERENCES rewards (id) ON DELETE CASCADE,
    user_id   BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    amount    INTEGER NOT NULL CHECK (amount >= 0),
    PRIMARY KEY (reward_id, user_id)
);

-- Rewards claimed before this migration were paid from the pair's bank. They are split between
-- the people by what each had earned, the last person taking the rounding remainder.
DO $$
DECLARE
    rw     RECORD;
    usr    RECORD;
    total  INTEGER;
    n      INTEGER;
    idx    INTEGER;
    paid   INTEGER;
    amount INTEGER;
BEGIN
    CREATE TEMP TABLE earned ON COMMIT DROP AS
    SELECT u.id AS user_id, COALESCE(sum(s.base_points + s.bonus_points), 0)::int AS pts
    FROM users u LEFT JOIN day_scores s ON s.user_id = u.id
    WHERE u.deleted_at IS NULL GROUP BY u.id;
    SELECT COALESCE(sum(pts), 0), count(*) INTO total, n FROM earned;
    IF n = 0 THEN RETURN; END IF;
    FOR rw IN SELECT id, spent FROM rewards WHERE status = 'claimed' LOOP
        idx := 0;
        paid := 0;
        FOR usr IN SELECT user_id, pts FROM earned ORDER BY user_id LOOP
            idx := idx + 1;
            IF idx = n THEN
                amount := rw.spent - paid;
            ELSIF total = 0 THEN
                amount := rw.spent / n;
            ELSE
                amount := round(rw.spent::numeric * usr.pts / total)::int;
            END IF;
            paid := paid + amount;
            INSERT INTO reward_payments (reward_id, user_id, amount) VALUES (rw.id, usr.user_id, amount);
        END LOOP;
    END LOOP;
END $$;

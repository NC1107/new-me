-- A new price on an approved reward is proposed again and waits for the other person. These keep
-- the approved state while it waits, so withdrawing or declining the change restores the reward
-- instead of losing it.
ALTER TABLE rewards
    ADD COLUMN approved_price INT,
    ADD COLUMN approved_focus BOOLEAN NOT NULL DEFAULT false;

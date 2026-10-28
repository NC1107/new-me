-- v13: more challenge kinds, a stored reason for the pick, a missed state, and separate push
-- switches for partner nudges, cover chances and habit approvals.

DO $$
DECLARE c TEXT;
BEGIN
    FOR c IN SELECT conname FROM pg_constraint
             WHERE conrelid = 'challenges'::regclass AND contype = 'c'
               AND pg_get_constraintdef(oid) LIKE '%counted_days%' LOOP
        EXECUTE format('ALTER TABLE challenges DROP CONSTRAINT %I', c);
    END LOOP;
END $$;

ALTER TABLE challenges
    ADD CONSTRAINT challenges_kind_known CHECK (kind IN ('steps', 'workouts', 'counted_days', 'reading',
        'sleep_nights', 'meal_days', 'protein_days', 'pushup_reps', 'yoga_minutes', 'habit_marks', 'active_days')),
    -- Why the kind was picked, in words the app can show. Challenges from before v13 have none.
    ADD COLUMN pick_reason TEXT CHECK (pick_reason IS NULL OR char_length(pick_reason) <= 200),
    -- Set once, at week end, on a challenge nobody finished. It costs nothing.
    ADD COLUMN missed_at TIMESTAMPTZ,
    ADD CONSTRAINT challenges_not_done_and_missed CHECK (completed_at IS NULL OR missed_at IS NULL);

-- "Partner finished their day" keeps notify_partner_done as the partner-counted switch.
ALTER TABLE users
    ADD COLUMN notify_partner_nudges BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_cover          BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN notify_approvals      BOOLEAN NOT NULL DEFAULT true;

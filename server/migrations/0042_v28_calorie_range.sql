-- v28: a daily calorie range replaces meals logged as the default food goal. Counting meals
-- rewards eating often rather than eating the right amount, and someone who logs the whole day
-- at once got a third of the goal for all of it.
--
-- The template's target is the range's half-width in percent. A day's snapshot holds the range
-- itself, low end as target and high end as target_alt, both in kcal; quest_target_ok takes
-- either shape because the two tables share it.

CREATE OR REPLACE FUNCTION quest_target_ok(key TEXT, target INTEGER, target_alt INTEGER) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(CASE key
        WHEN 'steps'            THEN target BETWEEN 1 AND 100000 AND target_alt IS NULL
        WHEN 'pushups'          THEN target BETWEEN 1 AND 500    AND target_alt IS NULL
        WHEN 'reading'          THEN target BETWEEN 1 AND 1440   AND target_alt BETWEEN 1 AND 2000
        WHEN 'meals_logged'     THEN target BETWEEN 1 AND 20     AND target_alt IS NULL
        WHEN 'calories'         THEN (target BETWEEN 5 AND 30 AND target_alt IS NULL)
                                  OR (target BETWEEN 500 AND 10000 AND target_alt BETWEEN target AND 12000)
        WHEN 'protein'          THEN target BETWEEN 1 AND 1000   AND target_alt IS NULL
        WHEN 'yoga'             THEN target BETWEEN 1 AND 1440   AND target_alt IS NULL
        WHEN 'exercise'         THEN target BETWEEN 5 AND 300    AND target_alt IS NULL
        WHEN 'sleep'            THEN target BETWEEN 240 AND 720  AND target_alt IS NULL
        WHEN 'water'            THEN target BETWEEN 250 AND 6000 AND target_alt IS NULL
        WHEN 'sleep_regularity' THEN target BETWEEN 15 AND 120   AND target_alt IS NULL
        WHEN 'produce'          THEN target BETWEEN 1 AND 30     AND target_alt IS NULL
        WHEN 'breathing'        THEN target BETWEEN 1 AND 60     AND target_alt IS NULL
        ELSE false
    END, false)
$$;

ALTER TABLE quest_templates
    DROP CONSTRAINT quest_templates_key_check,
    ADD CONSTRAINT quest_templates_key_check CHECK (key IN (
        'steps', 'pushups', 'reading', 'meals_logged', 'calories', 'protein', 'yoga', 'exercise', 'sleep',
        'water', 'sleep_regularity', 'produce', 'breathing'));

ALTER TABLE day_quests
    DROP CONSTRAINT day_quests_key_check,
    ADD CONSTRAINT day_quests_key_check CHECK (key IN (
        'steps', 'pushups', 'reading', 'meals_logged', 'calories', 'protein', 'yoga', 'exercise', 'sleep',
        'water', 'sleep_regularity', 'produce', 'breathing'));

-- A day's range has a high end but no second unit: it is one amount, not reading's minutes or
-- pages, so the pairing of target_alt with unit_alt no longer holds for calories.
ALTER TABLE day_quests
    DROP CONSTRAINT day_quests_check1,
    ADD CONSTRAINT day_quests_alt_unit_pair CHECK (key = 'calories' OR (target_alt IS NULL) = (unit_alt IS NULL));

-- Existing people get the range in the meals goal's place, on when meals logged was on and they
-- have a calorie target, and meals logged moves last and off. Days already snapshotted keep the
-- quests they started with, and the statements run in sequence so each sees the one before.
INSERT INTO quest_templates (user_id, key, target, unit, points, enabled, position)
SELECT u.id, 'calories', 10, '%', 20,
       COALESCE(m.enabled, true) AND u.kcal_target IS NOT NULL,
       COALESCE(m.position, (SELECT max(t.position) + 1 FROM quest_templates t WHERE t.user_id = u.id), 0)
FROM users u
LEFT JOIN quest_templates m ON m.user_id = u.id AND m.key = 'meals_logged'
ON CONFLICT (user_id, key) DO NOTHING;

UPDATE quest_templates m
SET enabled = false,
    position = (SELECT max(t.position) FROM quest_templates t WHERE t.user_id = m.user_id) + 1
WHERE m.key = 'meals_logged';

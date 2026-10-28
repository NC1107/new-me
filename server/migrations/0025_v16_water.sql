-- v16: the water quest. Drinks are logged by hand as water_ml or read from Health, and the
-- quest target follows the National Academies adequate intake for drinks by sex.

CREATE OR REPLACE FUNCTION quest_target_ok(key TEXT, target INTEGER, target_alt INTEGER) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(CASE key
        WHEN 'steps'        THEN target BETWEEN 1 AND 100000 AND target_alt IS NULL
        WHEN 'pushups'      THEN target BETWEEN 1 AND 500    AND target_alt IS NULL
        WHEN 'reading'      THEN target BETWEEN 1 AND 1440   AND target_alt BETWEEN 1 AND 2000
        WHEN 'meals_logged' THEN target BETWEEN 1 AND 20     AND target_alt IS NULL
        WHEN 'protein'      THEN target BETWEEN 1 AND 1000   AND target_alt IS NULL
        WHEN 'yoga'         THEN target BETWEEN 1 AND 1440   AND target_alt IS NULL
        WHEN 'exercise'     THEN target BETWEEN 5 AND 300    AND target_alt IS NULL
        WHEN 'sleep'        THEN target BETWEEN 240 AND 720  AND target_alt IS NULL
        WHEN 'water'        THEN target BETWEEN 250 AND 6000 AND target_alt IS NULL
        ELSE false
    END, false)
$$;

ALTER TABLE quest_templates
    DROP CONSTRAINT quest_templates_key_check,
    ADD CONSTRAINT quest_templates_key_check CHECK (key IN (
        'steps', 'pushups', 'reading', 'meals_logged', 'protein', 'yoga', 'exercise', 'sleep', 'water'));

ALTER TABLE day_quests
    DROP CONSTRAINT day_quests_key_check,
    ADD CONSTRAINT day_quests_key_check CHECK (key IN (
        'steps', 'pushups', 'reading', 'meals_logged', 'protein', 'yoga', 'exercise', 'sleep', 'water'));

ALTER TABLE activity_logs
    DROP CONSTRAINT activity_logs_type_known,
    DROP CONSTRAINT activity_logs_quantity_bounds,
    ADD CONSTRAINT activity_logs_type_known CHECK (type IN
        ('pushups', 'reading_minutes', 'reading_pages', 'yoga_minutes', 'other_minutes', 'water_ml')),
    ADD CONSTRAINT activity_logs_quantity_bounds CHECK (quantity > 0 AND quantity <= CASE type
        WHEN 'pushups' THEN 500
        WHEN 'reading_pages' THEN 2000
        WHEN 'water_ml' THEN 5000
        ELSE 1440
    END);

-- Existing people get the quest on, last in their order, with the target for their sex.
-- Days already snapshotted keep the quests they started with.
INSERT INTO quest_templates (user_id, key, target, unit, points, enabled, position)
SELECT u.id, 'water', CASE WHEN u.sex = 'male' THEN 3000 ELSE 2200 END, 'ml', 50, true,
       COALESCE((SELECT max(t.position) FROM quest_templates t WHERE t.user_id = u.id), -1) + 1
FROM users u
ON CONFLICT (user_id, key) DO NOTHING;

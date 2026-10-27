-- Health v2: seventeen daily metrics and the automatic exercise and sleep quests.

ALTER TABLE health_daily
    DROP CONSTRAINT health_daily_metric_check,
    DROP CONSTRAINT health_daily_check;

-- NaN sorts above every number in Postgres, so it fails the upper bounds too.
ALTER TABLE health_daily
    ADD CONSTRAINT health_daily_metric_check CHECK (metric IN (
        'steps', 'active_energy', 'basal_energy', 'exercise_minutes', 'distance_m', 'flights',
        'workouts', 'workout_minutes', 'sleep_minutes', 'mindful_minutes', 'water_ml',
        'resting_hr', 'hrv_ms', 'vo2max', 'weight_kg', 'body_fat_pct', 'lean_mass_kg')),
    ADD CONSTRAINT health_daily_value_bounds CHECK (CASE metric
        WHEN 'steps'            THEN value BETWEEN 0 AND 200000
        WHEN 'active_energy'    THEN value BETWEEN 0 AND 20000
        WHEN 'basal_energy'     THEN value BETWEEN 0 AND 20000
        WHEN 'exercise_minutes' THEN value BETWEEN 0 AND 1440
        WHEN 'distance_m'       THEN value BETWEEN 0 AND 200000
        WHEN 'flights'          THEN value BETWEEN 0 AND 1000
        WHEN 'workouts'         THEN value BETWEEN 0 AND 50
        WHEN 'workout_minutes'  THEN value BETWEEN 0 AND 1440
        WHEN 'sleep_minutes'    THEN value BETWEEN 0 AND 1440
        WHEN 'mindful_minutes'  THEN value BETWEEN 0 AND 1440
        WHEN 'water_ml'         THEN value BETWEEN 0 AND 20000
        WHEN 'resting_hr'       THEN value BETWEEN 20 AND 250
        WHEN 'hrv_ms'           THEN value BETWEEN 0 AND 500
        WHEN 'vo2max'           THEN value BETWEEN 0 AND 100
        WHEN 'weight_kg'        THEN value BETWEEN 20 AND 400
        WHEN 'body_fat_pct'     THEN value BETWEEN 1 AND 80
        WHEN 'lean_mass_kg'     THEN value BETWEEN 10 AND 300
        ELSE false
    END);

-- Trends read one metric over a date range.
CREATE INDEX health_daily_metric_day ON health_daily (user_id, metric, local_date DESC);

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
        ELSE false
    END, false)
$$;

ALTER TABLE quest_templates
    DROP CONSTRAINT quest_templates_key_check,
    ADD CONSTRAINT quest_templates_key_check CHECK (key IN (
        'steps', 'pushups', 'reading', 'meals_logged', 'protein', 'yoga', 'exercise', 'sleep'));

ALTER TABLE day_quests
    DROP CONSTRAINT day_quests_key_check,
    ADD CONSTRAINT day_quests_key_check CHECK (key IN (
        'steps', 'pushups', 'reading', 'meals_logged', 'protein', 'yoga', 'exercise', 'sleep'));

INSERT INTO quest_templates (user_id, key, target, unit, points, enabled, position)
SELECT u.id, n.key, n.target, 'min', n.points, false,
       COALESCE((SELECT max(t.position) FROM quest_templates t WHERE t.user_id = u.id), -1) + n.step
FROM users u
CROSS JOIN (VALUES ('exercise', 30, 100, 1), ('sleep', 420, 50, 2)) AS n (key, target, points, step)
ON CONFLICT (user_id, key) DO NOTHING;

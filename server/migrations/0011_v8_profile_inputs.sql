-- v8 research-backed targets: the profile inputs the formulas need. Height is entered once (or
-- synced from Health as the height_cm metric); sex is asked once; the goal defaults to maintain.
ALTER TABLE users
    ADD COLUMN height_cm    NUMERIC(4,1) CHECK (height_cm BETWEEN 100 AND 250),
    ADD COLUMN sex          TEXT CHECK (sex IN ('male', 'female')),
    ADD COLUMN goal_kind    TEXT NOT NULL DEFAULT 'maintain' CHECK (goal_kind IN ('lose', 'maintain', 'gain')),
    ADD COLUMN goal_pace_kg NUMERIC(3,2) NOT NULL DEFAULT 0 CHECK (goal_pace_kg BETWEEN 0 AND 1),
    ADD CONSTRAINT users_goal_pace CHECK ((goal_kind = 'maintain') = (goal_pace_kg = 0));

-- Height is a point-in-time reading, so it joins the daily metrics with the other body readings.
ALTER TABLE health_daily
    DROP CONSTRAINT health_daily_metric_check,
    DROP CONSTRAINT health_daily_value_bounds;

ALTER TABLE health_daily
    ADD CONSTRAINT health_daily_metric_check CHECK (metric IN (
        'steps', 'active_energy', 'basal_energy', 'exercise_minutes', 'distance_m', 'flights',
        'workouts', 'workout_minutes', 'sleep_minutes', 'mindful_minutes', 'water_ml',
        'resting_hr', 'hrv_ms', 'vo2max', 'weight_kg', 'body_fat_pct', 'lean_mass_kg', 'height_cm')),
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
        WHEN 'height_cm'        THEN value BETWEEN 100 AND 250
        ELSE false
    END);

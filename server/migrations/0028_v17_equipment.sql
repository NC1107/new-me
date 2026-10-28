-- v17: equipment tags follow what each exercise's own steps need. An inverted row hangs under a
-- bar at waist height, which a doorway pull-up bar cannot be, so it needs a low bar or rack; a
-- decline push-up puts the feet on a bench or box like a step-up or split squat does.

ALTER TABLE exercises
    DROP CONSTRAINT exercises_equipment_check,
    ADD CONSTRAINT exercises_equipment_check CHECK (equipment <@ ARRAY['pullup_bar', 'dumbbells', 'barbell',
        'bench', 'bands', 'dip_bars', 'hangboard', 'low_bar', 'gym']::text[]);

ALTER TABLE training_profiles
    DROP CONSTRAINT training_profiles_equipment_check,
    ADD CONSTRAINT training_profiles_equipment_check CHECK (equipment <@ ARRAY['pullup_bar', 'dumbbells',
        'barbell', 'bench', 'bands', 'dip_bars', 'hangboard', 'low_bar', 'gym']::text[]);

UPDATE exercises SET equipment = '{low_bar}' WHERE key = 'inverted_row' AND user_id IS NULL;
UPDATE exercises SET equipment = '{bench}' WHERE key = 'decline_push_up' AND user_id IS NULL;

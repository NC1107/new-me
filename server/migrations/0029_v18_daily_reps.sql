-- v18 daily reps: the "pushups" quest key stays for compatibility, but the person picks which
-- bodyweight exercise it counts. Existing rows are push-ups, which is what the column defaults to.

ALTER TABLE quest_templates
    ADD COLUMN exercise TEXT NOT NULL DEFAULT 'push_up' CHECK (exercise ~ '^[a-z0-9_]{2,60}$');

ALTER TABLE day_quests
    ADD COLUMN exercise TEXT NOT NULL DEFAULT 'push_up' CHECK (exercise ~ '^[a-z0-9_]{2,60}$');

-- A rep log of the quest records which exercise it was, so reps of another exercise never count
-- toward the chosen one. Logs of other types keep the default and ignore it.
ALTER TABLE activity_logs
    ADD COLUMN exercise TEXT NOT NULL DEFAULT 'push_up' CHECK (exercise ~ '^[a-z0-9_]{2,60}$');

CREATE INDEX activity_logs_reps ON activity_logs (user_id, exercise, local_date)
    WHERE type = 'pushups' AND deleted_at IS NULL;

-- Two easier choices for people who cannot yet do a full push-up or sit-up. Max tests of every
-- exercise already live in exercise_max_tests, so nothing else is added there.
INSERT INTO exercises (key, name, primary_muscles, secondary_muscles, measure, load, equipment, easier_key, harder_key, position,
                       steps, cues, images) VALUES
    ('knee_push_up', 'Knee push-up', '{chest}', '{triceps,shoulders,core}', 'reps', 'bodyweight', '{}', NULL, 'incline_push_up', 9,
     ARRAY['Start on your hands and knees with your hands a little wider than your shoulders.', 'Walk your knees back until your body is one straight line from head to knees.', 'Bend your elbows and lower your chest toward the floor.', 'Press back up to straight arms.']::text[],
     ARRAY['Keep your hips in line with your shoulders and knees.', 'Elbows point back about 45 degrees, not out to the sides.']::text[],
     ARRAY[]::text[]),
    ('crunch', 'Crunch', '{core}', '{}', 'reps', 'bodyweight', '{}', NULL, NULL, 54,
     ARRAY['Lie on your back with your knees bent and your feet flat on the floor.', 'Rest your hands lightly beside your head or across your chest.', 'Curl your shoulders off the floor by tightening your stomach.', 'Lower back down slowly.']::text[],
     ARRAY['Do not pull on your neck.', 'Move slowly; the lift is small.']::text[],
     ARRAY[]::text[]);

UPDATE exercises SET easier_key = 'knee_push_up' WHERE key = 'incline_push_up' AND user_id IS NULL;

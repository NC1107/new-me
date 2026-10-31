-- v19 calisthenics: a guided bodyweight session logs its minutes as their own activity type, which
-- counts toward exercise minutes and, from 20 minutes, as the day's strength session.

ALTER TABLE activity_logs
    DROP CONSTRAINT activity_logs_type_known,
    DROP CONSTRAINT activity_logs_quantity_bounds,
    ADD CONSTRAINT activity_logs_type_known CHECK (type IN
        ('pushups', 'reading_minutes', 'reading_pages', 'yoga_minutes', 'other_minutes', 'water_ml',
         'produce_servings', 'breathing_minutes', 'calisthenics_minutes')),
    ADD CONSTRAINT activity_logs_quantity_bounds CHECK (quantity > 0 AND quantity <= CASE type
        WHEN 'pushups' THEN 500
        WHEN 'reading_pages' THEN 2000
        WHEN 'water_ml' THEN 5000
        WHEN 'produce_servings' THEN 30
        WHEN 'breathing_minutes' THEN 120
        ELSE 1440
    END);

-- Zero-equipment exercises the four calisthenics levels need that the catalog lacked. They are
-- ordinary strength-kind exercises, so they also appear in the exercise library.
INSERT INTO exercises (key, name, primary_muscles, secondary_muscles, measure, load, equipment, easier_key, harder_key, position,
                       steps, cues, images) VALUES
    ('jumping_jack', 'Jumping jack', '{calves}', '{shoulders,quads}', 'seconds', 'bodyweight', '{}', NULL, NULL, 55,
     ARRAY['Stand tall with your feet together and your arms by your sides.', 'Jump your feet out wide while you swing your arms overhead.', 'Jump your feet back together and bring your arms down.', 'Keep a steady rhythm for the planned time.']::text[],
     ARRAY['Land softly on the balls of your feet.', 'Step out one foot at a time if jumping bothers your knees.']::text[],
     ARRAY[]::text[]),
    ('mountain_climber', 'Mountain climber', '{core}', '{shoulders,quads}', 'seconds', 'bodyweight', '{}', NULL, NULL, 56,
     ARRAY['Start in a high plank, with your hands under your shoulders and your body in one line.', 'Drive one knee toward your chest.', 'Switch legs, driving the other knee forward as the first foot goes back.', 'Keep switching at a steady pace for the planned time.']::text[],
     ARRAY['Keep your hips level, not piked up.', 'Slow down rather than let your back sag.']::text[],
     ARRAY[]::text[]),
    ('wall_sit', 'Wall sit', '{quads}', '{glutes,calves}', 'seconds', 'bodyweight', '{}', NULL, NULL, 57,
     ARRAY['Stand with your back against a wall and your feet about two feet out in front of you.', 'Slide down until your knees are bent to about 90 degrees.', 'Keep your back flat against the wall and your knees over your ankles.', 'Hold for the planned time, breathing steadily.']::text[],
     ARRAY['Rest your hands on your thighs, not on your knees.', 'Slide up a little if your knees hurt.']::text[],
     ARRAY[]::text[]),
    ('pike_push_up', 'Pike push-up', '{shoulders}', '{triceps,chest}', 'reps', 'bodyweight', '{}', 'push_up', NULL, 13,
     ARRAY['Start on your hands and feet with your hips high, so your body makes an upside-down V.', 'Bend your elbows and lower the top of your head toward the floor between your hands.', 'Press back up to straight arms.', 'Keep your legs as straight as you comfortably can.']::text[],
     ARRAY['Elbows point back, not out to the sides.', 'Walk your feet closer to your hands to make it harder.']::text[],
     ARRAY[]::text[]),
    ('jump_squat', 'Jump squat', '{quads}', '{glutes,calves}', 'reps', 'bodyweight', '{}', 'air_squat', NULL, 42,
     ARRAY['Stand with your feet about shoulder width apart.', 'Sit your hips back and bend your knees into a squat.', 'Jump up, driving through your whole foot and swinging your arms.', 'Land softly on bent knees and go straight into the next squat.']::text[],
     ARRAY['Land quietly, with your knees over your toes.', 'Do plain squats instead if jumping hurts your knees.']::text[],
     ARRAY[]::text[]);

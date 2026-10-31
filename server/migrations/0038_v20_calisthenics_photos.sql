-- v20: start and end photos for two of the exercises 0036 added without any, from free-exercise-db
-- (Unlicense) as in v12 and listed in server/static/exercises/SOURCES.tsv. The source has no wall
-- sit, pike push-up or jumping jack, so those keep their steps and no photo.
UPDATE exercises e
SET images = v.images
FROM (VALUES
    ('mountain_climber', ARRAY['mountain_climber-0.jpg', 'mountain_climber-1.jpg']::text[]),
    ('jump_squat', ARRAY['jump_squat-0.jpg', 'jump_squat-1.jpg']::text[])
) AS v (key, images)
WHERE e.key = v.key AND e.user_id IS NULL;

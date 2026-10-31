-- v19: what a quest is worth follows the effort its target asks (docs/design-v19-points.md).
-- Points are minutes x (MET - 1) in MET-minutes above rest, rounded to 5 and clamped to 20..150,
-- mirroring score.EffortPoints. Only the standing templates change; day_quests keep the points
-- they were frozen with, so old days score as they did.

UPDATE quest_templates t
SET points = LEAST(150, GREATEST(20, ((e.raw + 2) / 5) * 5))
FROM (
    SELECT id,
           CASE WHEN minutes10 IS NULL THEN 0
                ELSE (minutes10 * GREATEST(met10 - 10, 10) + 50) / 100 END AS raw
    FROM (
        SELECT id,
               CASE key
                   WHEN 'steps' THEN target * 10 / 100
                   WHEN 'exercise' THEN target * 10
                   WHEN 'pushups' THEN target * 10 * 10 / 60
                   WHEN 'yoga' THEN target * 10
                   WHEN 'breathing' THEN target * 10
                   WHEN 'reading' THEN target * 10
               END AS minutes10,
               CASE key
                   WHEN 'steps' THEN 38
                   WHEN 'exercise' THEN 38
                   WHEN 'pushups' THEN CASE exercise WHEN 'crunch' THEN 28 WHEN 'glute_bridge' THEN 30 ELSE 38 END
                   WHEN 'yoga' THEN 23
                   ELSE 10
               END AS met10
        FROM quest_templates
    ) m
) e
WHERE t.id = e.id;

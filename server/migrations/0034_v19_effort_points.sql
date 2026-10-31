-- v19: what a quest is worth follows the effort its target asks (docs/design-v19-points.md).
-- Points are minutes x (MET - 1) in MET-minutes above rest, rounded to 5 and clamped to 20..100,
-- mirroring score.EffortPoints. The strength quest (pushups) is priced as the person's planned
-- strength session, 30 minutes when there is none. Only the standing templates change;
-- day_quests keep the points they were frozen with, so old days score as they did.

UPDATE quest_templates t
SET points = LEAST(100, GREATEST(20, ((e.raw + 2) / 5) * 5))
FROM (
    SELECT id,
           CASE WHEN minutes10 IS NULL THEN 0
                ELSE (minutes10 * GREATEST(met10 - 10, 10) + 50) / 100 END AS raw
    FROM (
        SELECT q.id,
               CASE q.key
                   WHEN 'steps' THEN q.target * 10 / 100
                   WHEN 'exercise' THEN q.target * 10
                   WHEN 'pushups' THEN COALESCE(p.session_minutes, 30) * 10
                   WHEN 'yoga' THEN q.target * 10
                   WHEN 'breathing' THEN q.target * 10
                   WHEN 'reading' THEN q.target * 10
               END AS minutes10,
               CASE q.key
                   WHEN 'steps' THEN 38
                   WHEN 'exercise' THEN 38
                   WHEN 'pushups' THEN 35
                   WHEN 'yoga' THEN 23
                   ELSE 10
               END AS met10
        FROM quest_templates q
        LEFT JOIN training_profiles p ON p.user_id = q.user_id
    ) m
) e
WHERE t.id = e.id;

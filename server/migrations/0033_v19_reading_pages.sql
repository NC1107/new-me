-- v19: the pages way to finish the reading quest follows the minutes target (minutes x 238 words
-- a minute / 250 words a page, rounded) unless the person typed their own pages figure.
-- Only the standing template changes; day_quests keep the targets they were frozen with.

ALTER TABLE quest_templates ADD COLUMN target_alt_custom BOOLEAN NOT NULL DEFAULT false;

-- 15 was the old fixed default, so a template still on it was never chosen by the person.
UPDATE quest_templates SET target_alt_custom = true WHERE key = 'reading' AND target_alt IS DISTINCT FROM 15;

UPDATE quest_templates
SET target_alt = GREATEST(1, (target * 238 + 125) / 250)
WHERE key = 'reading' AND NOT target_alt_custom;

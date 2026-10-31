-- v19: the reading quest moves to a round rule, a page for each minute of reading (an audiobook
-- minute counts half, which lives in code). Templates that follow the minutes take the new pages
-- figure; a pages figure the person typed is left alone, and day_quests keep their frozen targets.
UPDATE quest_templates
SET target_alt = GREATEST(1, target)
WHERE key = 'reading' AND NOT target_alt_custom;

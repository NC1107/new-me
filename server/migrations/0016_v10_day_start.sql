-- v10: the day may start up to six hours after waking (Nick wakes at 3:40 and starts at 5:30).
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_first_notification_offset_min_check;
ALTER TABLE users ADD CONSTRAINT users_first_notification_offset_min_check
    CHECK (first_notification_offset_min BETWEEN 0 AND 360);

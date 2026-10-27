-- A time zone change is staged here and applied once no local date can repeat or be skipped.
ALTER TABLE users
    ADD COLUMN pending_timezone TEXT,
    ADD COLUMN pending_from DATE,
    ADD CONSTRAINT users_pending_zone_complete CHECK ((pending_timezone IS NULL) = (pending_from IS NULL));

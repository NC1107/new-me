-- v11: readiness can ease a day's session. eased is what the person was shown, kept once sets are
-- logged so the session never changes under them; full_session is their choice to take the full
-- session anyway, which sticks for the day.
ALTER TABLE training_sessions
    ADD COLUMN eased        BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN full_session BOOLEAN NOT NULL DEFAULT false;

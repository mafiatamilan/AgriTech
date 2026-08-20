-- Duration-based irrigation control.
-- Lets the farmer choose how many minutes the motor should run.

ALTER TABLE irrigation_events
    ADD COLUMN IF NOT EXISTS requested_duration_minutes INTEGER,
    ADD COLUMN IF NOT EXISTS stop_after TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual'
        CHECK (source IN ('manual', 'agent', 'schedule'));

CREATE INDEX IF NOT EXISTS idx_irrigation_events_stop_after
    ON irrigation_events(status, stop_after);

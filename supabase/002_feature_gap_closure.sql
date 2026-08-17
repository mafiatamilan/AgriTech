-- Feature Gap Closure Migration
-- Run after 001_initial_schema.sql

-- ============================================================
-- 1. Widen notifications.type CHECK constraint
-- ============================================================
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('watering', 'match', 'system', 'agent_result', 'shelf_life_expiring', 'sale_confirmed'));

-- ============================================================
-- 2. Add soil_type and area_locality to farmers
-- ============================================================
ALTER TABLE farmers ADD COLUMN IF NOT EXISTS soil_type TEXT;
ALTER TABLE farmers ADD COLUMN IF NOT EXISTS area_locality TEXT;

-- ============================================================
-- 3. farm_devices — pairs an ESP32/LoRa unit to a farm
-- ============================================================
CREATE TABLE IF NOT EXISTS farm_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    device_uid TEXT NOT NULL UNIQUE,
    device_secret_hash TEXT NOT NULL,
    last_signal_strength INTEGER,
    motor_relay_state TEXT DEFAULT 'off',
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_farm_devices_farm_id ON farm_devices(farm_id);
CREATE INDEX idx_farm_devices_device_uid ON farm_devices(device_uid);

ALTER TABLE farm_devices ENABLE ROW LEVEL SECURITY;
CREATE POLICY farm_devices_select ON farm_devices FOR SELECT
    USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY farm_devices_insert ON farm_devices FOR INSERT
    WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY farm_devices_update ON farm_devices FOR UPDATE
    USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- ============================================================
-- 4. hardware_status_events — ESP32 → cloud feedback
-- ============================================================
CREATE TABLE IF NOT EXISTS hardware_status_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_uid TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('heartbeat', 'motor_on', 'motor_off', 'error')),
    signal_strength INTEGER,
    payload JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_hardware_status_events_device_uid ON hardware_status_events(device_uid);
CREATE INDEX idx_hardware_status_events_created_at ON hardware_status_events(created_at);

-- Hardware status events are written by the service role, not by farmers directly.
-- RLS disabled for this table (admin-only writes).

-- ============================================================
-- 5. hardware_command_queue — queued commands for ESP32 to poll
-- ============================================================
CREATE TABLE IF NOT EXISTS hardware_command_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_uid TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('on', 'off')),
    issued_at TIMESTAMPTZ DEFAULT now(),
    delivered_at TIMESTAMPTZ
);

CREATE INDEX idx_hardware_command_queue_device_uid ON hardware_command_queue(device_uid);
CREATE INDEX idx_hardware_command_queue_delivered_at ON hardware_command_queue(delivered_at);

-- ============================================================
-- 6. vendors — vendor accounts
-- ============================================================
CREATE TABLE IF NOT EXISTS vendors (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    business_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY vendors_select ON vendors FOR SELECT USING (id = auth.farmer_id());
CREATE POLICY vendors_insert ON vendors FOR INSERT WITH CHECK (id = auth.farmer_id());
CREATE POLICY vendors_update ON vendors FOR UPDATE USING (id = auth.farmer_id());

-- ============================================================
-- 7. vendor_requests — what vendors need
-- ============================================================
CREATE TABLE IF NOT EXISTS vendor_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
    crop_name TEXT NOT NULL,
    quantity_needed NUMERIC,
    expected_price NUMERIC,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'matched', 'expired')),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_vendor_requests_vendor_id ON vendor_requests(vendor_id);
CREATE INDEX idx_vendor_requests_status ON vendor_requests(status);

ALTER TABLE vendor_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY vendor_requests_select ON vendor_requests FOR SELECT USING (vendor_id = auth.farmer_id());
CREATE POLICY vendor_requests_insert ON vendor_requests FOR INSERT WITH CHECK (vendor_id = auth.farmer_id());
CREATE POLICY vendor_requests_update ON vendor_requests FOR UPDATE USING (vendor_id = auth.farmer_id());

-- ============================================================
-- 8. chat_sessions + chat_messages
-- ============================================================
CREATE TABLE IF NOT EXISTS chat_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id UUID NOT NULL REFERENCES farmers(id) ON DELETE CASCADE,
    farm_id UUID REFERENCES farms(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_chat_sessions_farmer_id ON chat_sessions(farmer_id);

ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_sessions_select ON chat_sessions FOR SELECT USING (farmer_id = auth.farmer_id());
CREATE POLICY chat_sessions_insert ON chat_sessions FOR INSERT WITH CHECK (farmer_id = auth.farmer_id());

CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_chat_messages_session_id ON chat_messages(session_id);

ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_messages_select ON chat_messages FOR SELECT
    USING (session_id IN (SELECT id FROM chat_sessions WHERE farmer_id = auth.farmer_id()));
CREATE POLICY chat_messages_insert ON chat_messages FOR INSERT
    WITH CHECK (session_id IN (SELECT id FROM chat_sessions WHERE farmer_id = auth.farmer_id()));

-- ============================================================
-- 9. farmer_water_saved_totals view
-- ============================================================
CREATE OR REPLACE VIEW farmer_water_saved_totals AS
SELECT
    farmer_id,
    COALESCE(SUM(value), 0) AS total_water_saved_liters
FROM impact_metrics
WHERE metric_type = 'water_saved_liters'
GROUP BY farmer_id;

-- ============================================================
-- 10. Widen agent_results.agent_type CHECK to include all agent types
-- ============================================================
ALTER TABLE agent_results DROP CONSTRAINT IF EXISTS agent_results_agent_type_check;
ALTER TABLE agent_results ADD CONSTRAINT agent_results_agent_type_check
    CHECK (agent_type IN ('health', 'yield', 'next_season', 'inventory', 'demand_matching', 'soil_moisture'));

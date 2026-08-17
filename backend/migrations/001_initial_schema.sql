-- Smart Farming Platform - Initial Migration
-- Run against Supabase Postgres

-- Enable PostGIS for geospatial queries
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE farmers (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    preferred_language TEXT DEFAULT 'en',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE farms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id UUID NOT NULL REFERENCES farmers(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    location GEOGRAPHY(POINT, 4326),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE field_area (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    area_size NUMERIC,
    crop_type TEXT,
    planted_date DATE
);

CREATE TABLE crop_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    uploaded_at TIMESTAMPTZ DEFAULT now(),
    analysis_status TEXT DEFAULT 'pending' CHECK (analysis_status IN ('pending', 'done', 'failed'))
);

CREATE TABLE agent_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crop_image_id UUID REFERENCES crop_images(id) ON DELETE SET NULL,
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    agent_type TEXT NOT NULL CHECK (agent_type IN ('health', 'yield', 'next_season')),
    result_json JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE irrigation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    scheduled_time TIMESTAMPTZ NOT NULL,
    started_at TIMESTAMPTZ,
    stopped_at TIMESTAMPTZ,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'stopped', 'completed', 'cancelled')),
    moisture_reading NUMERIC,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE yield_forecasts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    crop_type TEXT NOT NULL,
    forecast_date DATE NOT NULL,
    expected_yield NUMERIC,
    confidence NUMERIC,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    crop_name TEXT NOT NULL,
    quantity NUMERIC NOT NULL DEFAULT 0,
    harvested_date DATE,
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE demand_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id UUID NOT NULL REFERENCES farmers(id) ON DELETE CASCADE,
    crop_name TEXT NOT NULL,
    shelf_life_days INTEGER,
    harvested_date DATE NOT NULL,
    expected_price NUMERIC,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'matched', 'expired')),
    shelf_life_expiry TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE rescue_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demand_request_id UUID NOT NULL REFERENCES demand_requests(id) ON DELETE CASCADE,
    matched_buyer_info JSONB NOT NULL DEFAULT '{}',
    matched_at TIMESTAMPTZ DEFAULT now(),
    status TEXT DEFAULT 'proposed' CHECK (status IN ('proposed', 'confirmed', 'rejected'))
);

CREATE TABLE impact_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id UUID NOT NULL REFERENCES farmers(id) ON DELETE CASCADE,
    metric_type TEXT NOT NULL,
    value NUMERIC NOT NULL,
    period TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id UUID NOT NULL REFERENCES farmers(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('watering', 'match', 'system')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    related_id UUID,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE sensor_readings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    moisture_pct NUMERIC NOT NULL,
    recorded_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_farms_farmer_id ON farms(farmer_id);
CREATE INDEX idx_field_area_farm_id ON field_area(farm_id);
CREATE INDEX idx_crop_images_farm_id ON crop_images(farm_id);
CREATE INDEX idx_agent_results_farm_id ON agent_results(farm_id);
CREATE INDEX idx_agent_results_created_at ON agent_results(created_at);
CREATE INDEX idx_irrigation_events_farm_id ON irrigation_events(farm_id);
CREATE INDEX idx_irrigation_events_status ON irrigation_events(status);
CREATE INDEX idx_irrigation_events_scheduled_time ON irrigation_events(scheduled_time);
CREATE INDEX idx_yield_forecasts_farm_id ON yield_forecasts(farm_id);
CREATE INDEX idx_inventory_farm_id ON inventory(farm_id);
CREATE INDEX idx_demand_requests_farmer_id ON demand_requests(farmer_id);
CREATE INDEX idx_demand_requests_status ON demand_requests(status);
CREATE INDEX idx_demand_requests_shelf_life_expiry ON demand_requests(shelf_life_expiry);
CREATE INDEX idx_rescue_matches_demand_request_id ON rescue_matches(demand_request_id);
CREATE INDEX idx_impact_metrics_farmer_id ON impact_metrics(farmer_id);
CREATE INDEX idx_notifications_farmer_id ON notifications(farmer_id);
CREATE INDEX idx_notifications_read_at ON notifications(read_at);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
CREATE INDEX idx_sensor_readings_farm_id ON sensor_readings(farm_id);
CREATE INDEX idx_sensor_readings_recorded_at ON sensor_readings(recorded_at);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE farmers ENABLE ROW LEVEL SECURITY;
ALTER TABLE farms ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_area ENABLE ROW LEVEL SECURITY;
ALTER TABLE crop_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE irrigation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE yield_forecasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE demand_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE rescue_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE impact_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_readings ENABLE ROW LEVEL SECURITY;

-- Helper function to get current farmer ID from JWT
CREATE OR REPLACE FUNCTION auth.farmer_id()
RETURNS UUID AS $$
  SELECT auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Farmers: can only read/update own profile
CREATE POLICY farmers_select ON farmers FOR SELECT
  USING (id = auth.farmer_id());
CREATE POLICY farmers_update ON farmers FOR UPDATE
  USING (id = auth.farmer_id());
CREATE POLICY farmers_insert ON farmers FOR INSERT
  WITH CHECK (id = auth.farmer_id());

-- Farms
CREATE POLICY farms_select ON farms FOR SELECT
  USING (farmer_id = auth.farmer_id());
CREATE POLICY farms_insert ON farms FOR INSERT
  WITH CHECK (farmer_id = auth.farmer_id());
CREATE POLICY farms_update ON farms FOR UPDATE
  USING (farmer_id = auth.farmer_id());

-- Field Area (via farm ownership)
CREATE POLICY field_area_select ON field_area FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY field_area_insert ON field_area FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY field_area_update ON field_area FOR UPDATE
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- Crop Images
CREATE POLICY crop_images_select ON crop_images FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY crop_images_insert ON crop_images FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY crop_images_update ON crop_images FOR UPDATE
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- Agent Results
CREATE POLICY agent_results_select ON agent_results FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY agent_results_insert ON agent_results FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- Irrigation Events
CREATE POLICY irrigation_events_select ON irrigation_events FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY irrigation_events_insert ON irrigation_events FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY irrigation_events_update ON irrigation_events FOR UPDATE
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- Yield Forecasts
CREATE POLICY yield_forecasts_select ON yield_forecasts FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY yield_forecasts_insert ON yield_forecasts FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- Inventory
CREATE POLICY inventory_select ON inventory FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY inventory_insert ON inventory FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY inventory_update ON inventory FOR UPDATE
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

-- Demand Requests
CREATE POLICY demand_requests_select ON demand_requests FOR SELECT
  USING (farmer_id = auth.farmer_id());
CREATE POLICY demand_requests_insert ON demand_requests FOR INSERT
  WITH CHECK (farmer_id = auth.farmer_id());
CREATE POLICY demand_requests_update ON demand_requests FOR UPDATE
  USING (farmer_id = auth.farmer_id());

-- Rescue Matches (via demand_request ownership)
CREATE POLICY rescue_matches_select ON rescue_matches FOR SELECT
  USING (demand_request_id IN (SELECT id FROM demand_requests WHERE farmer_id = auth.farmer_id()));
CREATE POLICY rescue_matches_insert ON rescue_matches FOR INSERT
  WITH CHECK (demand_request_id IN (SELECT id FROM demand_requests WHERE farmer_id = auth.farmer_id()));
CREATE POLICY rescue_matches_update ON rescue_matches FOR UPDATE
  USING (demand_request_id IN (SELECT id FROM demand_requests WHERE farmer_id = auth.farmer_id()));

-- Impact Metrics
CREATE POLICY impact_metrics_select ON impact_metrics FOR SELECT
  USING (farmer_id = auth.farmer_id());
CREATE POLICY impact_metrics_insert ON impact_metrics FOR INSERT
  WITH CHECK (farmer_id = auth.farmer_id());

-- Notifications
CREATE POLICY notifications_select ON notifications FOR SELECT
  USING (farmer_id = auth.farmer_id());
CREATE POLICY notifications_insert ON notifications FOR INSERT
  WITH CHECK (farmer_id = auth.farmer_id());
CREATE POLICY notifications_update ON notifications FOR UPDATE
  USING (farmer_id = auth.farmer_id());

-- Sensor Readings
CREATE POLICY sensor_readings_select ON sensor_readings FOR SELECT
  USING (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));
CREATE POLICY sensor_readings_insert ON sensor_readings FOR INSERT
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE farmer_id = auth.farmer_id()));

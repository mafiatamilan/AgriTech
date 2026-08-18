-- ============================================================
-- 004 — AI AGENT RUN CORRELATION + IMPACT METRICS EXTENSION
--
-- Safe to run after 001_initial_schema.sql, 002_updated.sql,
-- 003_updated.sql. Adds an agent_run_id to correlate every
-- artefact produced by a single LangGraph execution, and
-- extends impact_metrics with explainable baseline/optimized
-- values so the Tracks/Impact dashboard can show real numbers.
-- ============================================================

-- ------------------------------------------------------------
-- 1. AGENT RUN CORRELATION ID
-- ------------------------------------------------------------

ALTER TABLE agent_results
    ADD COLUMN IF NOT EXISTS agent_run_id UUID;

CREATE INDEX IF NOT EXISTS idx_agent_results_run
    ON agent_results(agent_run_id);

ALTER TABLE irrigation_decisions
    ADD COLUMN IF NOT EXISTS agent_run_id UUID;

CREATE INDEX IF NOT EXISTS idx_irrigation_decisions_run
    ON irrigation_decisions(agent_run_id);

ALTER TABLE smart_farming_reviews
    ADD COLUMN IF NOT EXISTS agent_run_id UUID;

CREATE INDEX IF NOT EXISTS idx_smart_farming_reviews_run
    ON smart_farming_reviews(agent_run_id);

ALTER TABLE mqtt_commands
    ADD COLUMN IF NOT EXISTS agent_run_id UUID;

CREATE INDEX IF NOT EXISTS idx_mqtt_commands_run
    ON mqtt_commands(agent_run_id);

ALTER TABLE yield_forecasts
    ADD COLUMN IF NOT EXISTS agent_run_id UUID;

CREATE INDEX IF NOT EXISTS idx_yield_forecasts_run
    ON yield_forecasts(agent_run_id);

-- ------------------------------------------------------------
-- 2. IMPACT METRICS EXTENSION
-- ------------------------------------------------------------

ALTER TABLE impact_metrics
    ADD COLUMN IF NOT EXISTS unit TEXT,

    ADD COLUMN IF NOT EXISTS baseline_value NUMERIC,

    ADD COLUMN IF NOT EXISTS optimized_value NUMERIC,

    ADD COLUMN IF NOT EXISTS source TEXT,

    ADD COLUMN IF NOT EXISTS measured_or_estimated TEXT
        DEFAULT 'estimated',

    ADD COLUMN IF NOT EXISTS agent_run_id UUID;

CREATE INDEX IF NOT EXISTS idx_impact_metrics_run
    ON impact_metrics(agent_run_id);

CREATE INDEX IF NOT EXISTS idx_impact_metrics_farm
    ON impact_metrics(farm_id);

-- RLS: farmer can always read their own impact rows (existing
-- policy keys off farmer_id). Extend with farm ownership scope
-- so rows are still readable via the /impact farm endpoint.

DROP POLICY IF EXISTS impact_metrics_select ON impact_metrics;

CREATE POLICY impact_metrics_select
ON impact_metrics
FOR SELECT
USING (
    farmer_id = public.farmer_id()
    OR farm_id IN (
        SELECT id FROM farms WHERE farmer_id = public.farmer_id()
    )
);

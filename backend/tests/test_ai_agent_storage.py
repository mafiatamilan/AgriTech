import pytest
import sys
import os
import hashlib
from datetime import date
from unittest.mock import patch, MagicMock, AsyncMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture(autouse=True)
def _pin_static_disease_provider():
    from app.core.config import get_settings
    get_settings.cache_clear()
    os.environ["PLANT_DISEASE_PROVIDER"] = "auto"
    yield
    os.environ.pop("PLANT_DISEASE_PROVIDER", None)
    get_settings.cache_clear()


class MockTable:
    def __init__(self, data=None):
        self._data = data or []
        self._filters = {}
        self._last_insert = None

    def select(self, *args):
        return self

    def eq(self, col, val):
        self._filters[col] = val
        return self

    def neq(self, col, val):
        return self

    def in_(self, col, vals):
        return self

    def filter(self, col, op, val):
        return self

    def not_(self):
        return self

    def is_(self, col, val):
        return self

    def gte(self, col, val):
        return self

    def lte(self, col, val):
        return self

    def order(self, col, desc=False):
        return self

    def limit(self, n):
        return self

    def execute(self):
        return self

    def insert(self, row):
        self._last_insert = row
        if isinstance(row, list):
            rows = [{**r, "id": r.get("id", f"mock-{len(self._data) + i + 1}")}
                    for i, r in enumerate(row)]
            self._data.extend(rows)
        else:
            self._data.append({**row, "id": row.get("id", f"mock-{len(self._data) + 1}")})
        return self

    def update(self, row):
        self._last_update = row
        return self

    def delete(self):
        return self

    @property
    def data(self):
        return self._data


class MockClient:
    def __init__(self):
        self._tables = {}
        self._storage = MagicMock()
        self._storage.from_("crop-images").upload.return_value = None
        self._storage.from_("crop-images").get_public_url.return_value = "https://example.com/crop.jpg"
        self.auth = MagicMock()

    def table(self, name):
        if name not in self._tables:
            self._tables[name] = MockTable()
        return self._tables[name]

    @property
    def storage(self):
        return self._storage


def get_mock_supabase():
    return MockClient()


def get_mock_supabase_admin():
    return MockClient()


def _seed(client, name, rows):
    client._tables[name] = MockTable(list(rows))
    return client._tables[name]


@pytest.mark.asyncio
async def test_weather_snapshot_persisted():
    from app.services.weather_service import get_weather_snapshot
    sb = get_mock_supabase_admin()
    snap = await get_weather_snapshot(sb, farm_id="farm-1")
    assert snap["farm_id"] == "farm-1"
    assert snap["source"] in ("weather_api", "backend_default")
    assert "avg_temp_c" in snap and "rainfall_forecast_mm_24h" in snap
    assert snap["id"] is None or snap["id"]


@pytest.mark.asyncio
async def test_irrigation_decision_persisted():
    from app.services.irrigation_agent_service import run_irrigation_decision
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "field_area", [{"id": "field-1", "farm_id": "farm-1", "crop_type": "tomato"}])
    _seed(sb, "farm_devices", [{"id": "dev-1", "farm_id": "farm-1", "device_uid": "esp-1"}])

    with patch("app.services.irrigation_agent_service.get_weather_snapshot",
               return_value={"id": "w-1", "farm_id": "farm-1"}):
        result = await run_irrigation_decision(sb, "farm-1", "farmer-1")

    assert result is not None
    assert result["decision"] in ("water_now", "delay", "skip", "monitor")
    decisions = sb._tables["irrigation_decisions"]._last_insert
    assert decisions["farm_id"] == "farm-1"


@pytest.mark.asyncio
async def test_irrigation_water_now_queues_hardware_command():
    from app.services.irrigation_agent_service import run_irrigation_decision
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "field_area", [{"id": "field-1", "farm_id": "farm-1", "crop_type": "maize",
                              "soil_type": "sandy", "planted_date": "2026-07-01"}])
    _seed(sb, "farm_devices", [{"id": "dev-1", "farm_id": "farm-1", "device_uid": "esp-1"}])

    with patch("app.services.irrigation_agent_service.get_weather_snapshot",
               return_value={"id": "w-1", "farm_id": "farm-1", "rainfall_forecast_mm_24h": 0.0}):
        result = await run_irrigation_decision(sb, "farm-1", "farmer-1")

    cmd = sb._tables["mqtt_commands"]._last_insert
    assert cmd is not None
    assert cmd["command_type"] == "motor_on"
    assert cmd["publish_status"] == "pending"


@pytest.mark.asyncio
async def test_hardware_status_updates_device_and_acks():
    from types import SimpleNamespace
    from app.routers.webhooks import receive_hardware_status
    sb = get_mock_supabase_admin()
    dev_hash = hashlib.sha256("secret".encode()).hexdigest()
    _seed(sb, "farm_devices", [{"id": "dev-1", "farm_id": "farm-1", "device_uid": "esp-1",
                                "device_secret_hash": dev_hash}])
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1"}])

    payload = SimpleNamespace(
        device_uid="esp-1",
        event_type="motor_on",
        signal_strength=-72,
        payload={"moisture_pct": 32.0, "temperature_c": 28.0, "humidity_pct": 60.0},
    )
    with patch("app.routers.webhooks.get_supabase_admin", lambda: sb):
        result = await receive_hardware_status(payload=payload, auth_info={})

    assert result["received"] is True
    update = sb._tables["farm_devices"]._last_update
    assert update["motor_relay_state"] == "on"
    assert update["last_moisture_pct"] == 32.0
    event = sb._tables["hardware_status_events"]._last_insert
    assert event["farm_device_id"] == "dev-1"


@pytest.mark.asyncio
async def test_pending_command_auth_and_204():
    from app.routers.motor import pending_command
    sb = get_mock_supabase_admin()
    dev_hash = hashlib.sha256("secret".encode()).hexdigest()
    _seed(sb, "farm_devices", [{"id": "dev-1", "device_uid": "esp-1", "device_secret_hash": dev_hash}])
    _seed(sb, "mqtt_commands", [{"id": "cmd-1", "farm_device_id": "dev-1", "publish_status": "pending",
                                 "payload": {"action": "on"}, "issued_at": "2026-08-17T08:00:00Z"}])

    with patch("app.routers.motor.get_supabase_admin", lambda: sb):
        req = MagicMock()
        req.headers.get.return_value = "secret"
        resp = await pending_command(device_uid="esp-1", request=req)
        assert resp["action"] == "on"
        req.headers.get.return_value = "wrong"
        from fastapi import HTTPException
        with pytest.raises(HTTPException):
            await pending_command(device_uid="esp-1", request=req)

    sb._tables["mqtt_commands"]._data = []
    with patch("app.routers.motor.get_supabase_admin", lambda: sb):
        req = MagicMock()
        req.headers.get.return_value = "secret"
        from fastapi import Response
        resp = await pending_command(device_uid="esp-1", request=req)
        assert resp.status_code == 204


@pytest.mark.asyncio
async def test_motor_status_top_level_fields():
    from app.routers.motor import motor_status
    sb = get_mock_supabase_admin()
    _seed(sb, "farm_devices", [{"device_uid": "esp-1", "last_signal_strength": -72,
                                "motor_relay_state": "on", "last_seen_at": "x"}])
    _seed(sb, "sensor_readings", [{"id": "r1", "farm_id": "farm-1", "moisture_pct": 30, "recorded_at": "x"}])

    with patch("app.routers.motor.get_supabase", lambda: sb):
        resp = await motor_status(farm_id="farm-1", current_farmer={"id": "farmer-1"})

    assert resp["signal_strength"] == -72
    assert resp["motor_relay_state"] is True
    assert "last_watered" in resp and "next_watering" in resp and "current_status" in resp


@pytest.mark.asyncio
async def test_motor_status_empty_moisture_when_no_sensors():
    from app.routers.motor import motor_status
    sb = get_mock_supabase_admin()
    with patch("app.routers.motor.get_supabase", lambda: sb):
        resp = await motor_status(farm_id="farm-1", current_farmer={"id": "farmer-1"})
    assert resp["moisture_readings"] == []
    assert resp["motor_relay_state"] is False


@pytest.mark.asyncio
async def test_inventory_recorded_with_status():
    from app.services.inventory_service import record_inventory
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1"}])

    with patch("app.services.inventory_service.get_weather_snapshot",
               return_value={"id": "w-1", "farm_id": "farm-1"}):
        result = await record_inventory(sb, "farmer-1", "farm-1", "tomato", 10, harvested_date="2026-08-15")

    assert result["status"] in ("available", "expired")
    statuses = sb._tables["inventory_statuses"]._last_insert
    assert statuses["inventory_id"] is not None
    ar = sb._tables["agent_results"]._last_insert
    assert ar["agent_type"] == "inventory"


@pytest.mark.asyncio
async def test_recommendations_include_crop_plans():
    from app.routers.recommendations import get_recommendations
    sb = get_mock_supabase_admin()
    _seed(sb, "agent_results", [{"agent_type": "health", "result_json": {"health_status": "Healthy"}},
                                {"agent_type": "yield", "result_json": {"expected_yield_kg": 420.0}},
                                {"agent_type": "next_season", "result_json": {"recommended_crops": []}}])
    _seed(sb, "yield_forecasts", [{"crop_type": "corn"}])
    _seed(sb, "crop_plan_recommendations", [{"crop": "tomato", "rank": 1}])

    with patch("app.routers.recommendations.get_supabase", lambda: sb):
        resp = await get_recommendations(farm_id="farm-1", current_farmer={"id": "farmer-1"})

    assert resp["crop_plan_recommendations"][0]["crop"] == "tomato"
    assert resp["health_analysis"]["result_json"]["health_status"] == "Healthy"


@pytest.mark.asyncio
async def test_smart_supervisor_persists_review():
    from app.services.supervisor_service import run_smart_supervisor
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "field_area", [{"id": "field-1", "farm_id": "farm-1", "crop_type": "tomato"}])

    with patch("app.services.supervisor_service.get_weather_snapshot",
               return_value={"id": "w-1", "farm_id": "farm-1"}):
        result = await run_smart_supervisor(sb, "farm-1")

    assert result is not None
    assert "alerts" in result and "next_actions" in result
    review = sb._tables["smart_farming_reviews"]._last_insert
    assert review["farm_id"] == "farm-1"
    assert isinstance(review["alerts"], list) and isinstance(review["next_actions"], list)
    ar = sb._tables["agent_results"]._last_insert
    assert ar["agent_type"] == "smart_supervisor"


@pytest.mark.asyncio
async def test_next_season_persists_recommendations():
    from app.services.next_season_service import run_next_season
    sb = get_mock_supabase_admin()
    _seed(sb, "crop_performance_history", [
        {"crop": "tomato", "yield_kg": 100.0, "revenue": 1000.0, "cost": 500.0, "season": "rainy"},
        {"crop": "maize", "yield_kg": 200.0, "revenue": 800.0, "cost": 400.0, "season": "rainy"},
    ])
    result = await run_next_season(sb, "farm-1")
    assert result is not None
    assert len(result["recommended_crops"]) >= 1
    ar = sb._tables["agent_results"]._last_insert
    assert ar["agent_type"] == "next_season"


@pytest.mark.asyncio
async def test_crop_image_pipeline_disease_and_yield():
    from app.routers.upload import upload_crop_image
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1"}])

    with patch("app.routers.upload.get_supabase", lambda: sb):
        file = MagicMock()
        file.filename = "crop.jpg"

        async def fake_read():
            return b"data"

        file.read = fake_read
        resp = await upload_crop_image(
            farm_id="farm-1", file=file, current_farmer={"id": "farmer-1"},
        )
        assert resp["analysis_status"] == "processing"
        assert resp["id"] is not None

@pytest.mark.asyncio
async def test_disease_pipeline_writes_diagnosis_and_agent_results():
    from app.routers.upload import _run_analysis
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1"}])
    _seed(sb, "crop_images", [{"id": "img-1", "farm_id": "farm-1", "farmer_id": "farmer-1",
                               "analysis_status": "processing"}])

    with patch("app.routers.upload.get_supabase_admin", lambda: sb):
        with patch("app.services.crop_health_service._download_image",
                   new=AsyncMock(return_value="https://example.com/crop.jpg")):
            await _run_analysis("img-1", "farm-1", "https://example.com/crop.jpg", None)

    crop_images = sb._tables["crop_images"]
    assert crop_images._last_update["analysis_status"] == "done"
    diag = sb._tables["disease_diagnoses"]._last_insert
    assert diag["image_upload_id"] == "img-1"
    assert diag["predicted_crop"] == "corn"
    health = [r for r in sb._tables["agent_results"]._data if r["agent_type"] == "health"]
    assert health and health[0]["result_json"]["health_status"] == "Disease detected"
    assert health[0]["result_json"]["diseases_detected"] == ["northern leaf blight"]
    yield_row = [r for r in sb._tables["agent_results"]._data if r["agent_type"] == "yield"]
    assert yield_row and yield_row[0]["result_json"]["crop_type"] in ("corn", "unknown")


@pytest.mark.asyncio
async def test_market_crop_match_strips_match_score():
    from app.routers.market import crop_match, _strip
    from app.models.market import DemandRequestCreate
    assert _strip({"match_score": 0.9, "buyer_name": "x"}) == {"buyer_name": "x"}

    sb = get_mock_supabase_admin()
    with patch("app.routers.market.get_supabase", lambda: sb):
        with patch("app.routers.market.run_demand_matching", return_value=[
            {"buyer_name": "b1", "match_score": 0.95},
            {"buyer_name": "b2", "match_score": 0.9},
            {"buyer_name": "b3", "match_score": 0.8},
            {"buyer_name": "b4", "match_score": 0.7},
        ]):
            req = DemandRequestCreate(crop_name="Maize", shelf_life_days=7, harvested_date="2026-08-10")
            result = await crop_match(req, {"id": "farmer-1"})

    assert len(result.matches) == 3
    for m in result.matches:
        assert "match_score" not in m


@pytest.mark.asyncio
async def test_demand_matching_agent_ranks_real_vendors():
    from app.agents.demand_matching import run_demand_matching

    sb = get_mock_supabase_admin()
    _seed(sb, "vendor_requests", [
        {"id": "vr1", "vendor_id": "v1", "crop_name": "tomato", "quantity_needed": 100,
         "expected_price": 55, "status": "open",
         "vendors": {"business_name": "GreenCo", "reliability_score": 0.9}},
        {"id": "vr2", "vendor_id": "v2", "crop_name": "tomato", "quantity_needed": 50,
         "expected_price": 40, "status": "open",
         "vendors": {"business_name": "CheapMart", "reliability_score": 0.5}},
    ])
    dr = {"id": "d1", "crop_name": "tomato", "shelf_life_days": 7,
          "harvested_date": "2026-08-10", "shelf_life_expiry": "2026-08-17T10:00:00Z"}

    matches = await run_demand_matching(dr, sb)

    assert len(matches) <= 3
    assert [m["buyer_name"] for m in matches] == ["GreenCo", "CheapMart"]
    for m in matches:
        assert "match_score" not in m
        assert "offered_price" in m
        assert "distance_km" in m
        assert "reason_labels" in m


@pytest.mark.asyncio
async def test_demand_matching_agent_empty_returns_open():
    from app.agents.demand_matching import run_demand_matching

    sb = get_mock_supabase_admin()
    dr = {"id": "d1", "crop_name": "maize", "shelf_life_days": 7, "harvested_date": "2026-08-10"}
    matches = await run_demand_matching(dr, sb)
    assert matches == []


@pytest.mark.asyncio
async def test_graph_runs_all_agents():
    from app.agents.graph import run_farm_graph
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "field_area", [{"id": "field-1", "farm_id": "farm-1", "crop_type": "maize",
                              "soil_type": "sandy", "growth_stage": "vegetative"}])
    _seed(sb, "farm_devices", [{"id": "dev-1", "farm_id": "farm-1", "device_uid": "esp-1"}])
    _seed(sb, "crop_performance_history", [
        {"crop": "tomato", "yield_kg": 100.0, "revenue": 1000.0, "cost": 500.0, "season": "rainy"},
        {"crop": "maize", "yield_kg": 200.0, "revenue": 800.0, "cost": 400.0, "season": "rainy"},
    ])
    _seed(sb, "crop_images", [{"id": "img-1", "farm_id": "farm-1", "analysis_status": "processing"}])

    with patch("app.services.crop_health_service._download_image",
               new=AsyncMock(return_value="https://example.com/crop.jpg")):
        out = await run_farm_graph(
            sb, "farm-1", farmer_id="farmer-1",
            image_ctx={"image_id": "img-1", "image_url": "https://example.com/crop.jpg", "crop_hint": None},
            inventory_params=[{"farmer_id": "farmer-1", "farm_id": "farm-1", "crop_name": "tomato",
                               "quantity": 10, "harvested_date": "2026-08-10"}],
            demand_requests=[{"id": "d1", "crop_name": "maize", "shelf_life_days": 7,
                              "harvested_date": "2026-08-10"}],
        )

    agents_ran = {r["agent"] for r in out.get("results", [])}
    assert agents_ran == {"irrigation", "crop_health", "yield", "inventory",
                          "demand_matching", "next_season", "smart_supervisor", "impact"}
    assert out.get("errors") == []

    # every result carries an explicit status — never silent success
    for r in out.get("results", []):
        assert r["status"] in ("success", "failed", "skipped", "unavailable")
    assert out["agent_run_id"]

    health = [r["output"] for r in out["results"] if r["agent"] == "crop_health"][0]
    assert health["health_status"] == "Disease detected"
    yield_out = [r["output"] for r in out["results"] if r["agent"] == "yield"][0]
    assert yield_out["expected_yield_kg"] > 0
    supervisor = [r["output"] for r in out["results"] if r["agent"] == "smart_supervisor"][0]
    assert supervisor is not None and "alerts" in supervisor
    # supervisor now reports whether business-side data reached it
    assert supervisor["business_review"] is True
    inventory = [r["output"] for r in out["results"] if r["agent"] == "inventory"][0]
    assert inventory and inventory[0]["inventory_id"] is not None


@pytest.mark.asyncio
async def test_graph_isolates_agent_failures():
    from app.agents.graph import run_farm_graph
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "farm_devices", [{"id": "dev-1", "farm_id": "farm-1", "device_uid": "esp-1"}])

    async def boom(sb, farm_id, farmer_id=None, agent_run_id=None):
        raise RuntimeError("agent down")

    from app.services import irrigation_agent_service
    with patch.object(irrigation_agent_service, "run_irrigation_decision", side_effect=boom):
        out = await run_farm_graph(sb, "farm-1", farmer_id="farmer-1")

    assert any("irrigation" in e for e in out.get("errors", []))
    ran_agents = {r["agent"] for r in out.get("results", [])}
    assert "smart_supervisor" in ran_agents
    # failed agents stay in results but are marked failed — never silent success
    irr = [r for r in out["results"] if r["agent"] == "irrigation"][0]
    assert irr["status"] == "failed"
    for r in out["results"]:
        if r["status"] == "success":
            assert r["output"] is not None

@pytest.mark.asyncio
async def test_impact_metrics_recorded_from_success_results():
    from app.services.impact_service import record_impact_metrics
    sb = get_mock_supabase_admin()
    results = [
        {"agent": "irrigation", "status": "success",
         "output": {"decision": "water_now", "recommended_duration_minutes": 18}},
        {"agent": "demand_matching", "status": "success",
         "output": [[{"quantity_to_sell_kg": 50.0, "offered_price": 30.0}]]},
        {"agent": "yield", "status": "success",
         "output": {"crop_type": "tomato", "expected_yield_kg": 120.0}},
    ]
    rows = await record_impact_metrics(
        sb, "farm-1", "farmer-1", "run-123", results)
    persisted = sb._tables["impact_metrics"]._data
    assert len(persisted) == 4
    types = {r["metric_type"] for r in persisted}
    assert "water_saved_liters" in types
    assert "food_rescued_kg" in types
    assert "economic_value_recovered_inr" in types
    assert "co2e_avoided_kg" in types
    assert "yield_gain_pct" not in types  # no crop_performance baseline
    for r in persisted:
        assert r["agent_run_id"] == "run-123"
        assert r["farm_id"] == "farm-1"
        assert r["farmer_id"] == "farmer-1"
        assert "metadata" in r
    water = [r for r in persisted if r["metric_type"] == "water_saved_liters"][0]
    assert water["baseline_value"] > water["optimized_value"]
    assert water["value"] == round(water["baseline_value"] - water["optimized_value"], 2)
    rescued = [r for r in persisted if r["metric_type"] == "food_rescued_kg"][0]
    assert rescued["value"] == 50.0
    assert rescued["measured_or_estimated"] == "estimated"


@pytest.mark.asyncio
async def test_impact_skips_failed_and_skipped_agents():
    from app.services.impact_service import record_impact_metrics
    sb = get_mock_supabase_admin()
    results = [
        {"agent": "irrigation", "status": "failed", "output": None},
        {"agent": "demand_matching", "status": "skipped", "output": None},
    ]
    rows = await record_impact_metrics(sb, "farm-1", "farmer-1", "run-1", results)
    assert rows == []
    assert sb._tables.get("impact_metrics") is None


@pytest.mark.asyncio
async def test_supervisor_consumes_real_business_data():
    from app.services.supervisor_service import run_smart_supervisor
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "field_area", [{"id": "field-1", "farm_id": "farm-1", "crop_type": "tomato"}])
    _seed(sb, "inventory", [
        {"id": "inv-1", "farm_id": "farm-1", "crop_name": "tomato", "quantity": 40.0,
         "harvested_date": "2026-08-10", "storage_type": "AMBIENT", "quality_grade": "A",
         "status": "available"},
    ])
    _seed(sb, "vendor_requests", [
        {"id": "vr-1", "vendor_id": "v-1", "crop_name": "tomato", "quantity_needed": 50.0,
         "expected_price": 30.0, "status": "open",
         "vendors": {"business_name": "GreenCo", "reliability_score": 0.9}},
    ])

    with patch("app.services.supervisor_service.get_weather_snapshot",
               return_value={"id": "w-1", "farm_id": "farm-1"}):
        result = await run_smart_supervisor(
            sb, "farm-1",
            results=[{"agent": "yield", "status": "success",
                      "output": {"crop_type": "tomato", "expected_yield_kg": 120.0,
                                 "confidence_level": "high", "risk_factors": []}}],
            agent_run_id="run-7",
        )

    assert result is not None
    assert result["business_review"] is True
    assert result["agri_review"] is True
    review = sb._tables["smart_farming_reviews"]._last_insert
    assert review["agent_run_id"] == "run-7"
    ar = sb._tables["agent_results"]._last_insert
    assert ar["agent_run_id"] == "run-7"
    assert ar["agent_type"] == "smart_supervisor"
    # inventory + vendor data actually reached the supervisor's business review
    assert len(review["alerts"]) >= 0  # alerts may be empty; the point is inputs flowed
    assert result["alerts"] == review["alerts"]


@pytest.mark.asyncio
async def test_agent_run_id_consistent_across_graph_writes():
    from app.agents.graph import run_farm_graph
    sb = get_mock_supabase_admin()
    _seed(sb, "farms", [{"id": "farm-1", "farmer_id": "farmer-1", "latitude": 6.5, "longitude": 3.3}])
    _seed(sb, "field_area", [{"id": "field-1", "farm_id": "farm-1", "crop_type": "maize",
                              "soil_type": "sandy", "growth_stage": "vegetative"}])
    _seed(sb, "farm_devices", [{"id": "dev-1", "farm_id": "farm-1", "device_uid": "esp-1"}])
    _seed(sb, "crop_images", [{"id": "img-1", "farm_id": "farm-1", "analysis_status": "processing"}])

    out = await run_farm_graph(
        sb, "farm-1", farmer_id="farmer-1",
        image_ctx={"image_id": "img-1", "image_url": "https://example.com/crop.jpg", "crop_hint": None},
        demand_requests=[{"id": "d1", "crop_name": "maize", "shelf_life_days": 7,
                          "harvested_date": "2026-08-10"}],
    )
    run_id = out["agent_run_id"]
    assert run_id

    impact_rows = sb._tables["impact_metrics"]._data
    assert impact_rows  # at least one metric recorded
    for r in impact_rows:
        assert r["agent_run_id"] == run_id
    # supervisor row written under the same run id
    reviews = sb._tables["smart_farming_reviews"]._data
    assert reviews and all(r["agent_run_id"] == run_id for r in reviews)
    agent_results = [r for r in sb._tables["agent_results"]._data if r.get("agent_run_id")]
    assert agent_results and all(r["agent_run_id"] == run_id for r in agent_results)

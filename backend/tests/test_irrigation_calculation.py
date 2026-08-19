"""Irrigation calculation tests for the volume-based duration model."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "agents"))

from datetime import date

from agri_agents.irrigation_agent import WaterIrrigationAgent
from agri_agents.models import CropFieldContext, SoilType, WeatherSnapshot

TODAY = date(2026, 8, 19)


def _ctx(**kw):
    defaults = dict(
        farm_id="f1",
        field_id="fd1",
        crop="tomato",
        soil_type=SoilType.LOAMY,
        planting_date=date(2026, 8, 10),
        field_area_m2=500,
        pump_flow_lpm=12,
    )
    defaults.update(kw)
    return CropFieldContext(**defaults)


def _weather(**kw):
    defaults = dict(avg_temp_c=28, max_temp_c=32, humidity_pct=70)
    defaults.update(kw)
    return WeatherSnapshot(**defaults)


def test_larger_field_area_produces_larger_volume():
    agent = WaterIrrigationAgent()
    small = agent.decide(_ctx(field_area_m2=100), _weather(), TODAY)
    large = agent.decide(_ctx(field_area_m2=500), _weather(), TODAY)
    assert small.estimated_water_volume_liters < large.estimated_water_volume_liters


def test_different_pump_flows_produce_different_runtimes():
    agent = WaterIrrigationAgent()
    slow = agent.decide(_ctx(pump_flow_lpm=10), _weather(), TODAY)
    fast = agent.decide(_ctx(pump_flow_lpm=20), _weather(), TODAY)
    assert slow.recommended_duration_minutes != fast.recommended_duration_minutes


def test_higher_pump_flow_shorter_runtime():
    agent = WaterIrrigationAgent()
    slow = agent.decide(_ctx(pump_flow_lpm=12), _weather(), TODAY)
    fast = agent.decide(_ctx(pump_flow_lpm=24), _weather(), TODAY)
    assert fast.recommended_duration_minutes < slow.recommended_duration_minutes


def test_runtime_equals_volume_over_pump_flow():
    agent = WaterIrrigationAgent()
    d = agent.decide(_ctx(), _weather(), TODAY)
    expected = max(1, round(d.estimated_water_need_mm * 500 / 12))
    assert d.recommended_duration_minutes == expected
    assert d.estimated_water_volume_liters == round(d.estimated_water_need_mm * 500, 1)


def test_soil_type_changes_water_requirement():
    agent = WaterIrrigationAgent()
    sandy = agent.decide(_ctx(soil_type=SoilType.SANDY), _weather(), TODAY)
    clay = agent.decide(_ctx(soil_type=SoilType.CLAY), _weather(), TODAY)
    assert sandy.estimated_water_need_mm > clay.estimated_water_need_mm


def test_weather_changes_water_requirement():
    agent = WaterIrrigationAgent()
    cool = agent.decide(_ctx(), _weather(avg_temp_c=22, humidity_pct=80), TODAY)
    hot = agent.decide(_ctx(), _weather(avg_temp_c=38, humidity_pct=30), TODAY)
    assert hot.estimated_water_need_mm > cool.estimated_water_need_mm


def test_rainfall_reduces_irrigation_requirement():
    agent = WaterIrrigationAgent()
    dry = agent.decide(_ctx(), _weather(rainfall_mm_today=0), TODAY)
    rain = agent.decide(
        _ctx(),
        _weather(rainfall_mm_today=8, rainfall_forecast_mm_24h=5),
        TODAY,
    )
    assert rain.estimated_water_need_mm < dry.estimated_water_need_mm


def test_planting_date_affects_growth_stage():
    agent = WaterIrrigationAgent()
    recent = agent.decide(_ctx(planting_date=date(2026, 8, 17)), _weather(), TODAY)
    old = agent.decide(_ctx(planting_date=date(2026, 1, 1)), _weather(), TODAY)
    assert recent.growth_stage.stage != old.growth_stage.stage


def test_missing_pump_flow_uses_documented_fallback_safely():
    agent = WaterIrrigationAgent()
    d = agent.decide(_ctx(pump_flow_lpm=None), _weather(), TODAY)
    assert d.pump_flow_estimated is True
    assert d.estimated_water_volume_liters is None
    expected = max(
        1,
        round(d.estimated_water_need_mm / agent.LEGACY_PUMP_DELIVERY_MM_PER_MIN),
    )
    assert d.recommended_duration_minutes == expected
    assert "estimated" in d.recommendation.lower()
    assert any("fallback" in r.lower() for r in d.reason_labels)
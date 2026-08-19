import pytest


def test_performance_defaults_weather_summary_to_object():
    from app.routers.performance import CropPerformanceCreate

    request = CropPerformanceCreate(farm_id="farm-1", crop="wheat")
    assert request.weather_summary == {}


def test_inventory_json_model_accepts_flutter_payload():
    from app.routers.inventory import InventoryCreate

    request = InventoryCreate.model_validate({
        "farm_id": "farm-1",
        "crop_name": "Wheat",
        "quantity": 150,
        "harvested_date": "2026-05-14T00:00:00.000Z",
        "quality_grade": "A",
    })
    assert request.quantity == 150
    assert request.crop_name == "Wheat"

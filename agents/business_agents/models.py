from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from enum import Enum
from typing import Optional


class StorageType(str, Enum):
    AMBIENT = "ambient"
    SHADED = "shaded"
    EVAPORATIVE_COOLER = "evaporative_cooler"
    REFRIGERATED = "refrigerated"


class Urgency(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    URGENT = "urgent"
    EXPIRED_RISK = "expired_risk"


@dataclass(frozen=True)
class CropProfile:
    crop: str
    plant_type: str
    base_shelf_life_days: float
    ideal_temp_min_c: float
    ideal_temp_max_c: float
    ideal_humidity_min_pct: float
    ideal_humidity_max_pct: float
    temp_sensitivity: float
    humidity_sensitivity: float
    rain_sensitivity: float
    damage_sensitivity: float = 1.0


@dataclass(frozen=True)
class WeatherSnapshot:
    avg_temp_c: float
    max_temp_c: float
    humidity_pct: float
    rainfall_mm: float = 0.0
    condition: str = "clear"
    transport_risk: float = 0.0


@dataclass(frozen=True)
class InventoryBatch:
    batch_id: str
    crop: str
    quantity_kg: float
    harvest_date: date
    storage_type: StorageType = StorageType.AMBIENT
    quality_grade: str = "A"
    farm_id: Optional[str] = None


@dataclass(frozen=True)
class ShelfLifeEstimate:
    crop: str
    plant_type: str
    estimated_shelf_life_days: float
    remaining_shelf_life_days: float
    sell_by_date: date
    urgency: Urgency
    spoilage_risk: str
    recommendation: str
    factors: tuple[str, ...]


@dataclass(frozen=True)
class InventoryStatus:
    batch_id: str
    crop: str
    quantity_kg: float
    quality_grade: str
    harvest_date: date
    storage_type: StorageType
    shelf_life: ShelfLifeEstimate


@dataclass(frozen=True)
class BuyerDemand:
    buyer_id: str
    buyer_name: str
    crop: str
    quantity_requested_kg: float
    offered_price_per_kg: float
    distance_km: float
    pickup_in_hours: float
    buyer_reliability: float = 0.8
    transport_available: bool = True


@dataclass(frozen=True)
class BuyerOption:
    rank: int
    buyer_id: str
    buyer_name: str
    crop: str
    quantity_requested_kg: float
    quantity_to_sell_kg: float
    offered_price_per_kg: float
    estimated_revenue: float
    distance_km: float
    pickup_in_hours: float
    recommendation: str
    reason_labels: tuple[str, ...]


@dataclass(frozen=True)
class DemandMatchResult:
    crop: str
    batch_id: str
    quantity_available_kg: float
    urgency: Urgency
    top_matches: tuple[BuyerOption, ...]
    message: str


@dataclass(frozen=True)
class CropPerformance:
    crop: str
    sales_kg: float
    avg_price_per_kg: float
    production_cost_per_kg: float
    unsold_or_waste_kg: float
    demand_growth_pct: float = 0.0
    market_price_trend_pct: float = 0.0


@dataclass(frozen=True)
class FarmSideSignal:
    crop: str
    expected_yield_kg: Optional[float] = None
    yield_confidence: Optional[float] = None
    soil_suitability: Optional[float] = None
    water_availability: Optional[float] = None
    disease_risk: Optional[float] = None


@dataclass(frozen=True)
class CropPlanRecommendation:
    rank: int
    crop: str
    expected_profit_per_kg: float
    demand_outlook: str
    waste_risk: str
    planning_risk: str
    recommendation: str
    reason_labels: tuple[str, ...]
    suggested_crop_mix_pct: Optional[int] = None


@dataclass(frozen=True)
class CropPlanResult:
    recommendations: tuple[CropPlanRecommendation, ...]
    message: str
    farm_side_inputs_used: bool


@dataclass(frozen=True)
class BusinessReview:
    inventory: tuple[InventoryStatus, ...] = field(default_factory=tuple)
    demand_matches: tuple[DemandMatchResult, ...] = field(default_factory=tuple)
    crop_plan: Optional[CropPlanResult] = None

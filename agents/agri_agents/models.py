from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from enum import Enum
from typing import Any, Optional


class ConfidenceLevel(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    UNCERTAIN = "uncertain"


class GrowthStage(str, Enum):
    GERMINATION = "germination"
    SEEDLING = "seedling"
    VEGETATIVE = "vegetative"
    FLOWERING = "flowering"
    FRUITING = "fruiting"
    MATURITY = "maturity"
    UNKNOWN = "unknown"


class SoilType(str, Enum):
    SANDY = "sandy"
    LOAMY = "loamy"
    SILTY = "silty"
    CLAY = "clay"
    PEATY = "peaty"


class IrrigationUrgency(str, Enum):
    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


@dataclass(frozen=True)
class WeatherSnapshot:
    avg_temp_c: float
    max_temp_c: float
    humidity_pct: float
    rainfall_mm_today: float = 0.0
    rainfall_forecast_mm_24h: float = 0.0
    sunlight_hours: float = 7.0
    wind_speed_kmph: float = 8.0
    condition: str = "clear"


@dataclass(frozen=True)
class CropCalendar:
    crop: str
    germination_days: int
    seedling_days: int
    vegetative_days: int
    flowering_days: int
    fruiting_days: int
    maturity_days: int


@dataclass(frozen=True)
class GrowthStageEstimate:
    stage: GrowthStage
    source: str
    confidence: ConfidenceLevel
    days_after_planting: Optional[int] = None


@dataclass(frozen=True)
class CropFieldContext:
    farm_id: str
    field_id: str
    crop: str
    soil_type: SoilType
    planting_date: Optional[date] = None
    growth_stage: Optional[GrowthStage] = None
    last_irrigation_date: Optional[date] = None
    auto_irrigation_enabled: bool = False


@dataclass(frozen=True)
class MqttIrrigationCommand:
    topic: str
    payload: dict[str, Any]
    qos: int = 1
    retain: bool = False


@dataclass(frozen=True)
class IrrigationDecision:
    field_id: str
    crop: str
    growth_stage: GrowthStageEstimate
    irrigation_needed: bool
    urgency: IrrigationUrgency
    recommended_duration_minutes: int
    estimated_water_need_mm: float
    recommendation: str
    reason_labels: tuple[str, ...]
    mqtt_command: Optional[MqttIrrigationCommand] = None


@dataclass(frozen=True)
class ModelPrediction:
    label: str
    confidence: float


@dataclass(frozen=True)
class PlantDiseaseDiagnosis:
    crop: str
    disease: str
    is_healthy: bool
    confidence_level: ConfidenceLevel
    severity: str
    recommendation: str
    remedies: tuple[str, ...]
    prevention: tuple[str, ...]
    retake_image: bool
    reason_labels: tuple[str, ...]


@dataclass(frozen=True)
class YieldPredictionSignal:
    crop: str
    expected_yield_kg: Optional[float] = None
    confidence_level: Optional[ConfidenceLevel] = None
    risk_factors: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class AgriReview:
    disease: Optional[PlantDiseaseDiagnosis] = None
    irrigation: Optional[IrrigationDecision] = None
    yield_prediction: Optional[YieldPredictionSignal] = None
    alerts: tuple[str, ...] = field(default_factory=tuple)

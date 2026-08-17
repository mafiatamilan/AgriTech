"""Farm-side agents for the smart farming multi-agent platform."""

from .disease_agent import DiseasePredictionAgent, StaticPlantVillageModelAdapter
from .irrigation_agent import SoilMoistureIrrigationAgent, SoilTypeIrrigationAgent
from .model_adapters import (
    KerasPlantVillageModelAdapter,
    PDDDPlantDiseaseModelAdapter,
    RoboflowPlantVillageModelAdapter,
    TFLitePlantVillageModelAdapter,
)
from .supervisor import AgriSupervisorAgent

__all__ = [
    "AgriSupervisorAgent",
    "DiseasePredictionAgent",
    "KerasPlantVillageModelAdapter",
    "PDDDPlantDiseaseModelAdapter",
    "RoboflowPlantVillageModelAdapter",
    "SoilMoistureIrrigationAgent",
    "SoilTypeIrrigationAgent",
    "StaticPlantVillageModelAdapter",
    "TFLitePlantVillageModelAdapter",
]

"""Farm-side agents for the smart farming multi-agent platform."""

from .disease_agent import DiseasePredictionAgent, StaticPlantVillageModelAdapter
from .irrigation_agent import SoilMoistureIrrigationAgent, SoilTypeIrrigationAgent
from .model_adapters import ViTPlantDiseaseModelAdapter
from .supervisor import AgriSupervisorAgent

__all__ = [
    "AgriSupervisorAgent",
    "DiseasePredictionAgent",
    "SoilMoistureIrrigationAgent",
    "SoilTypeIrrigationAgent",
    "StaticPlantVillageModelAdapter",
    "ViTPlantDiseaseModelAdapter",
]

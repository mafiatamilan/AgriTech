from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    SUPABASE_URL: str = ""
    SUPABASE_ANON_KEY: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""
    SUPABASE_JWT_SECRET: str = ""
    DATABASE_URL: str = ""
    AGENT_WEBHOOK_SECRET: str = ""
    AGENT_DISPATCH_URL: str = "http://localhost:8000/webhooks/agent-result"
    HARDWARE_COMMAND_SECRET: str = ""
    WEATHER_API_KEY: str = ""
    WEATHER_API_BASE_URL: str = ""
    LLM_API_KEY: str = ""
    LLM_API_BASE_URL: str = ""
    LLM_PROVIDER: str = ""
    LLM_MODEL: str = "nemotron-3-ultra-free"

    # Plant disease model provider: pddd, roboflow, or auto
    PLANT_DISEASE_PROVIDER: str = "auto"
    PDDD_MODEL_PATH: str = "models/mobilenet_v3_large-model-84.pth"
    PDDD_LABELS_PATH: str = "models/class_indices.json"

    # Impact metric constants (demo factors — configurable, never magic numbers)
    PUMP_FLOW_LITERS_PER_MIN: float = 40.0
    DEFAULT_WATERING_MINUTES: float = 30.0
    CO2E_FACTOR_KG_PER_KG_FOOD: float = 2.5
    INDIAN_RUPEE_PER_USD: float = 83.0

    # Debug / logging
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}


@lru_cache
def get_settings() -> Settings:
    return Settings()

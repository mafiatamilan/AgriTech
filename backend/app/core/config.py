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
    RELAY_ENABLED: bool = True
    RELAY_PORT: str = "/dev/ttyUSB1"
    RELAY_BAUD_RATE: int = 115200
    LORA_GATEWAY_STATUS_URL: str = "http://10.33.12.68/status"
    LORA_GATEWAY_TIMEOUT_SECONDS: float = 0.6
    WEATHER_API_KEY: str = ""
    WEATHER_API_BASE_URL: str = ""
    FCM_SERVER_KEY: str = ""

    # Plant disease model provider: vit, roboflow, or auto
    PLANT_DISEASE_PROVIDER: str = "vit"
    VIT_MODEL_NAME: str = "wambugu71/crop_leaf_diseases_vit"

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

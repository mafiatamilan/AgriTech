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

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


@lru_cache
def get_settings() -> Settings:
    return Settings()

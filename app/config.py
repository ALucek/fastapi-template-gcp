from typing import Optional
from pydantic import Field, AnyHttpUrl, ValidationError
from pydantic_settings import BaseSettings
from functools import lru_cache
import os

class Settings(BaseSettings):
    port: int = Field(default=int(os.getenv("PORT", 8080)))
    api_key: Optional[str] = Field(default=None, env="API_KEY")
    app_auth_enabled: bool = Field(default=False, env="APP_AUTH_ENABLED")

    api_key_header: str = Field(default="x-api-key")
    service_name: str = "fastapi-cloudrun"
    service_version: str = "1.0.0"
    enable_cors: bool = False
    cors_allow_origins: list[AnyHttpUrl] = []

    class Config:
        case_sensitive = False

@lru_cache()
def get_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as e:
        raise RuntimeError(f"Configuration error: {e}") from e
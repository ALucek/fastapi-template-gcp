from pydantic import Field, ValidationError
from pydantic_settings import BaseSettings
from functools import lru_cache
import os

class Settings(BaseSettings):
    port: int = Field(default=int(os.getenv("PORT", 8080)))
    service_name: str = "fastapi-cloudrun"
    service_version: str = "1.0.0"

    class Config:
        case_sensitive = False

@lru_cache()
def get_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as e:
        raise RuntimeError(f"Configuration error: {e}") from e
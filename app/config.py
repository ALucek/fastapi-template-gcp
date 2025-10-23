from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr, ValidationError, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

import os
import pathlib

def _env_or_file(name: str) -> str | None:
    """Return the value of NAME from env or from NAME_FILE if present."""
    file_path = os.getenv(f"{name}_FILE")
    if file_path and pathlib.Path(file_path).exists():
        return pathlib.Path(file_path).read_text().strip()
    return os.getenv(name)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(".env.app", ".env"), case_sensitive=False, extra="ignore")

    port: int = Field(default=8080, validation_alias=AliasChoices("PORT", "APP_PORT"))
    service_name: str = "fastapi-cloudrun"
    service_version: str = "1.0.0"
    log_level: Literal["CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG", "NOTSET"] = "INFO"
    log_json: bool = True

    # Example secret (injected via Cloud Run --set-secrets or local .env)
    api_token: SecretStr | None = Field(default=None)

    def __init__(self, **data):
        # Support *_FILE fallback commonly used when secrets are mounted as files
        data.setdefault("api_token", _env_or_file("API_TOKEN"))
        super().__init__(**data)

    @field_validator("log_level", mode="before")
    @classmethod
    def _normalize_log_level(cls, value: str) -> str:
        if isinstance(value, str):
            upper_value = value.upper()
            if upper_value in {"CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG", "NOTSET"}:
                return upper_value
        return value

@lru_cache()
def get_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as e:
        raise RuntimeError(f"Configuration error: {e}") from e
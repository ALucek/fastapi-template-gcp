from pydantic import BaseSettings, Field, AnyHttpUrl, ValidationError
from functools import lru_cache
import os

class Settings(BaseSettings):
    # Cloud Run sets PORT; default to 8080 for local/dev
    port: int = Field(default=int(os.getenv("PORT", 8080)))
    # API key is injected via Secret Manager -> env var at deploy time
    api_key: str = Field(..., env="API_KEY")
    # allow customizing the header name if ever needed
    api_key_header: str = Field(default="x-api-key")
    # service metadata (for logs)
    service_name: str = "fastapi-cloudrun"
    service_version: str = "1.0.0"
    # CORS toggle if needed later
    enable_cors: bool = False
    cors_allow_origins: list[AnyHttpUrl] = []

    class Config:
        case_sensitive = False

@lru_cache()
def get_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as e:
        # Fail fast if secrets are missing in prod
        raise RuntimeError(f"Configuration error: {e}") from e

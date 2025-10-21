from fastapi import Header, HTTPException, status, Depends
from app.config import get_settings

def require_api_key(
    x_api_key: str | None = Header(default=None),
    settings = Depends(get_settings)
) -> None:
    # ✅ if app-level auth is disabled, do nothing
    if not settings.app_auth_enabled:
        return
    # if enabled, enforce header match
    if not x_api_key or x_api_key != settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized: missing or invalid API key",
        )

from fastapi import APIRouter, Depends
from app.deps import auth_dep
from app.config import get_settings

settings = get_settings()
router = APIRouter(prefix="/v1",
                   dependencies=[Depends(auth_dep)] if settings.app_auth_enabled else [])


@router.get("/hello")
def hello():
    return {"message": "hello, authorized client"}

# Example unprotected health endpoints (leave open)
@router.get("/healthz")
def healthz():
    return {"status": "ok"}

@router.get("/readyz")
def readyz():
    # Insert real checks here if needed
    return {"status": "ready"}

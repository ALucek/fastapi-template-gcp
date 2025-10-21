from fastapi import APIRouter, Depends
from app.deps import auth_dep

router = APIRouter(prefix="/v1")

@router.get("/hello", dependencies=[Depends(auth_dep)])
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

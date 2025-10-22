from fastapi import APIRouter
from .schemas import HelloResponse, HealthzResponse

router = APIRouter(prefix="/v1")


@router.get("/hello", response_model=HelloResponse)
def hello() -> HelloResponse:
    return HelloResponse(message="hello, authorized client")

@router.get("/healthz", response_model=HealthzResponse)
def healthz() -> HealthzResponse:
    return HealthzResponse(status="ok")

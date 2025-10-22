from pydantic import BaseModel


class HelloResponse(BaseModel):
    message: str


class HealthzResponse(BaseModel):
    status: str



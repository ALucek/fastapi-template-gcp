from fastapi import FastAPI
from app.config import get_settings
from app.utils.logging import configure_logging
from app.api.v1.routes import router as v1_router

def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings=settings)

    app = FastAPI(
        title=settings.service_name,
        version=settings.service_version,
        docs_url="/docs", openapi_url="/openapi.json",
    )

    # Mount routers
    app.include_router(v1_router)
    return app

app = create_app()

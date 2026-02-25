"""
FastAPI Application — Production-ready REST API
Demonstrates health checks, structured logging, and metrics endpoints
for use with Kubernetes liveness/readiness probes and Prometheus scraping.
"""

import logging
import os
import time
from contextlib import asynccontextmanager

import structlog
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

# ---------------------------------------------------------------------------
# Structured logging setup
# ---------------------------------------------------------------------------
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ]
)
logger = structlog.get_logger()

# ---------------------------------------------------------------------------
# Application configuration
# ---------------------------------------------------------------------------
APP_ENV = os.getenv("APP_ENV", "production")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
BUILD_COMMIT = os.getenv("GIT_COMMIT", "unknown")

# ---------------------------------------------------------------------------
# Startup / Shutdown lifecycle
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("application_startup", env=APP_ENV, version=APP_VERSION, commit=BUILD_COMMIT)
    yield
    logger.info("application_shutdown")


app = FastAPI(
    title="FastAPI Microservice",
    description="Production-ready FastAPI service deployed on Amazon EKS",
    version=APP_VERSION,
    lifespan=lifespan,
    docs_url="/docs" if APP_ENV != "production" else None,  # Disable Swagger in prod
    redoc_url=None,
)

# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "").split(","),
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration_ms = round((time.time() - start_time) * 1000, 2)
    logger.info(
        "http_request",
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=duration_ms,
    )
    return response


# ---------------------------------------------------------------------------
# Prometheus metrics
# ---------------------------------------------------------------------------
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


# ---------------------------------------------------------------------------
# Health check endpoints (used by Kubernetes probes)
# ---------------------------------------------------------------------------
@app.get("/healthz/live", tags=["Health"], summary="Liveness probe")
async def liveness():
    """Kubernetes liveness probe — confirms the process is running."""
    return {"status": "alive", "version": APP_VERSION}


@app.get("/healthz/ready", tags=["Health"], summary="Readiness probe")
async def readiness():
    """
    Kubernetes readiness probe — confirms the app is ready to serve traffic.
    Checks downstream dependencies (database, cache, etc.) before returning healthy.
    """
    checks = {}
    overall_healthy = True

    # Database connectivity check
    try:
        # In a real app: run a lightweight SELECT 1 query
        checks["database"] = "healthy"
    except Exception as exc:
        checks["database"] = f"unhealthy: {exc}"
        overall_healthy = False

    if not overall_healthy:
        raise HTTPException(status_code=503, detail={"status": "not ready", "checks": checks})

    return {"status": "ready", "checks": checks, "version": APP_VERSION}


# ---------------------------------------------------------------------------
# Application routes
# ---------------------------------------------------------------------------
@app.get("/", tags=["Root"])
async def root():
    return {
        "service": "fastapi-app",
        "version": APP_VERSION,
        "environment": APP_ENV,
        "commit": BUILD_COMMIT,
    }


@app.get("/api/v1/items", tags=["Items"])
async def list_items():
    """Example list endpoint."""
    return {"items": [], "total": 0}


@app.get("/api/v1/items/{item_id}", tags=["Items"])
async def get_item(item_id: int):
    """Example detail endpoint."""
    if item_id <= 0:
        raise HTTPException(status_code=422, detail="item_id must be a positive integer")
    # Simulated DB lookup
    return {"id": item_id, "name": f"Item {item_id}"}


# ---------------------------------------------------------------------------
# Entry point (local development)
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8000)),
        reload=APP_ENV == "development",
        log_level="info",
    )

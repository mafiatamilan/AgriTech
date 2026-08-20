import time
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.routing import APIRoute
from app.core.logging_config import setup_logging, get_logger
from app.routers import (
    auth, farms, motor, market, upload, webhooks,
    recommendations, settings, account, notifications,
    vendors, inventory, performance, impact,
)
from app.workers.scheduler import start_scheduler, stop_scheduler

setup_logging()
logger = get_logger("app.main")


class LoggingMiddleware:
    """Log every inbound request and its response time + status."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        import urllib.parse
        request = Request(scope)
        path = request.url.path
        if request.query_params:
            path = f"{path}?{urllib.parse.urlencode(request.query_params)}"
        logger.info(">>> %s %s", scope.get("method"), path)

        start = time.perf_counter()
        status_holder = {}

        async def wrapped_send(message):
            if message["type"] == "http.response.start":
                status_holder["status"] = message["status"]
                duration_ms = (time.perf_counter() - start) * 1000
                logger.info(
                    "<<< %s %s -> %s (%d ms)",
                    scope.get("method"), path, message["status"], duration_ms,
                )
            await send(message)

        await self.app(scope, receive, wrapped_send)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _ensure_storage_bucket()
    start_scheduler()
    logger.info("Backend started (lifespan up)")
    yield
    stop_scheduler()
    logger.info("Backend stopped (lifespan down)")


def _ensure_storage_bucket():
    try:
        from app.db.supabase_client import get_supabase_admin
        sb = get_supabase_admin()
        existing = {b.id for b in sb.storage.list_buckets()}
        if "crop-images" not in existing:
            sb.storage.create_bucket("crop-images")
            sb.storage.update_bucket("crop-images", {"public": True})
    except Exception:
        # non-fatal: storage uploads will surface a clear error if still missing
        pass


app = FastAPI(
    title="Smart Farming API",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(LoggingMiddleware)

app.include_router(auth.router)
app.include_router(farms.router)
app.include_router(motor.router)
app.include_router(market.router)
app.include_router(upload.router)
app.include_router(recommendations.router)
app.include_router(settings.router)
app.include_router(account.router)
app.include_router(notifications.router)
app.include_router(webhooks.router)
app.include_router(vendors.router)
app.include_router(inventory.router)
app.include_router(performance.router)
app.include_router(impact.router)


@app.get("/health")
async def health():
    return {"status": "ok"}

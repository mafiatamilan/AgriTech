from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.routers import (
    auth, farms, motor, market, upload, webhooks,
    recommendations, settings, account, notifications,
    vendors, chat, inventory, performance, impact,
)
from app.workers.scheduler import start_scheduler, stop_scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    _ensure_storage_bucket()
    start_scheduler()
    yield
    stop_scheduler()


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
app.include_router(chat.router)
app.include_router(inventory.router)
app.include_router(performance.router)
app.include_router(impact.router)


@app.get("/health")
async def health():
    return {"status": "ok"}

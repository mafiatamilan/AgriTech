from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.routers import (
    auth, farms, motor, market, upload,
    recommendations, settings, account, notifications,
)
from app.workers.scheduler import start_scheduler, stop_scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()
    yield
    stop_scheduler()


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


@app.get("/health")
async def health():
    return {"status": "ok"}

"""Crop image health + yield analysis orchestration.

Runs the DiseasePredictionAgent (writes `disease_diagnoses` + an `agent_results`
health row) and the yield prediction (writes an `agent_results` yield row +
`yield_forecasts`). Shared by the /upload router and the LangGraph orchestrator.
"""

from datetime import date
from pathlib import Path
import logging
import tempfile

import httpx

from app.agents.runtime import agents
from app.core.config import get_settings

logger = logging.getLogger("agritech.crop_health")


async def _download_image(image_url: str) -> str:
    """Ensure the image is available as a local path (agents need one)."""
    if Path(image_url).exists():
        return image_url
    suffix = Path(image_url).suffix.lower() or ".jpg"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.close()
    try:
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            resp = await client.get(image_url)
            resp.raise_for_status()
            with open(tmp.name, "wb") as f:
                f.write(resp.content)
        logger.debug("Downloaded image %s -> %s (%d bytes)", image_url, tmp.name, len(resp.content))
        return tmp.name
    except Exception:
        Path(tmp.name).unlink(missing_ok=True)
        raise


async def run_crop_health(
    sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None,
    agent_run_id: str | None = None,
) -> dict:
    agri = agents()["agri"]

    model, model_name = _build_model_adapter(agri)
    local_path = await _download_image(image_url)
    try:
        diag = agri.DiseasePredictionAgent(model_adapter=model).analyze_image(local_path, crop_hint=crop_hint)
    finally:
        if local_path != image_url:
            Path(local_path).unlink(missing_ok=True)

    health_result = _health_result_from_diagnosis(diag)

    sb.table("disease_diagnoses").insert({
        "farm_id": farm_id,
        "image_upload_id": image_id,
        "predicted_crop": diag.crop,
        "predicted_disease": diag.disease,
        "is_healthy": diag.is_healthy,
        "confidence_level": diag.confidence_level.value,
        "raw_confidence": getattr(model, "confidence", None),
        "severity": diag.severity,
        "recommendation": diag.recommendation,
        "remedies": list(diag.remedies),
        "prevention": list(diag.prevention),
        "retake_image": diag.retake_image,
        "reason_labels": list(diag.reason_labels),
        "model_source": "vit" if model_name == "ViTPlantDiseaseModelAdapter" else "static",
        "model_name": model_name,
        "model_version": "1",
    }).execute()

    sb.table("agent_results").insert({
        "crop_image_id": image_id,
        "image_upload_id": image_id,
        "farm_id": farm_id,
        "agent_type": "health",
        "result_json": health_result,
        "model_name": model_name,
        "model_version": "1",
        "agent_run_id": agent_run_id,
    }).execute()

    return health_result


async def run_yield_analysis(
    sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None,
    agent_run_id: str | None = None, disease_info: dict | None = None,
) -> dict:
    from app.agents.yield_prediction import run_yield_prediction
    from app.services.weather_service import get_weather_snapshot

    # Fetch weather data for the farm
    weather_data = None
    try:
        farm_resp = sb.table("farms").select("latitude, longitude").eq("id", farm_id).execute()
        if farm_resp.data:
            farm = farm_resp.data[0]
            weather_data = await get_weather_snapshot(
                sb, farm_id=farm_id, crop=crop_hint,
                farm_lat=farm.get("latitude"), farm_lon=farm.get("longitude"),
            )
    except Exception as exc:
        logger.warning("Could not fetch weather for yield prediction: %s", exc)

    result = await run_yield_prediction(
        image_url, crop_hint=crop_hint, disease_info=disease_info,
        weather_data=weather_data,
    )

    sb.table("agent_results").insert({
        "crop_image_id": image_id,
        "image_upload_id": image_id,
        "farm_id": farm_id,
        "agent_type": "yield",
        "result_json": result,
        "model_name": "YieldHeuristicIndia",
        "model_version": "1",
        "agent_run_id": agent_run_id,
    }).execute()

    sb.table("yield_forecasts").insert({
        "farm_id": farm_id,
        "crop_type": result["crop_type"],
        "forecast_date": date.today().isoformat(),
        "expected_yield": result["expected_yield_kg"],
        "confidence": None,
        "model_name": "YieldHeuristicIndia",
        "model_version": "1",
        "risk_factors": result.get("risk_factors", []),
        "agent_run_id": agent_run_id,
    }).execute()

    return result


def _build_model_adapter(agri):
    """Build the disease model adapter from PLANT_DISEASE_PROVIDER config.

    vit → HuggingFace ViT model (default: wambugu71/crop_leaf_diseases_vit).
    auto/anything else → static demo adapter.
    Falls back to the static adapter if the selected provider cannot load.
    """
    settings = get_settings()
    provider = (settings.PLANT_DISEASE_PROVIDER or "auto").lower()

    if provider == "vit":
        try:
            return agri.ViTPlantDiseaseModelAdapter(
                model_name=settings.VIT_MODEL_NAME,
            ), "ViTPlantDiseaseModelAdapter"
        except Exception:
            pass  # transformers missing / download failure → fall through

    return agri.StaticPlantVillageModelAdapter(
        label="Corn___Northern_Leaf_Blight", confidence=0.92
    ), "StaticPlantVillageModelAdapter"


def _health_result_from_diagnosis(diag) -> dict:
    diseases = [] if (diag.is_healthy or diag.disease in (None, "", "uncertain")) else [diag.disease]
    if diag.retake_image:
        health_status = "Image unclear — retake"
    elif diag.is_healthy:
        health_status = "Healthy"
    else:
        health_status = "Disease detected"
    return {
        "health_status": health_status,
        "crop": diag.crop,
        "disease": diag.disease if not diag.is_healthy else "healthy",
        "diseases_detected": diseases,
        "is_healthy": diag.is_healthy,
        "confidence_level": diag.confidence_level.value,
        "severity": diag.severity,
        "recommendation": diag.recommendation,
        "remedies": list(diag.remedies),
        "prevention": list(diag.prevention),
        "retake_image": diag.retake_image,
        "reason_labels": list(diag.reason_labels),
    }

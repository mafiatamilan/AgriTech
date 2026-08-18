"""Crop image health + yield analysis orchestration.

Runs the DiseasePredictionAgent (writes `disease_diagnoses` + an `agent_results`
health row) and the yield prediction (writes an `agent_results` yield row +
`yield_forecasts`). Shared by the /upload router and the LangGraph orchestrator.
"""

from datetime import date
from pathlib import Path

from app.agents.runtime import agents
from app.core.config import get_settings


async def run_crop_health(
    sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None,
    agent_run_id: str | None = None,
) -> dict:
    agri = agents()["agri"]

    model, model_name = _build_model_adapter(agri)
    diag = agri.DiseasePredictionAgent(model_adapter=model).analyze_image(image_url, crop_hint=crop_hint)

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
        "model_source": "plantvillage-static" if model_name == "StaticPlantVillageModelAdapter" else "pddd",
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
    agent_run_id: str | None = None,
) -> dict:
    from app.agents.yield_prediction import run_yield_prediction
    result = await run_yield_prediction(image_url, [], crop_hint=crop_hint)

    sb.table("agent_results").insert({
        "crop_image_id": image_id,
        "image_upload_id": image_id,
        "farm_id": farm_id,
        "agent_type": "yield",
        "result_json": result,
        "model_name": "YieldPredictionStub",
        "model_version": "1",
        "agent_run_id": agent_run_id,
    }).execute()

    sb.table("yield_forecasts").insert({
        "farm_id": farm_id,
        "crop_type": result["crop_type"],
        "forecast_date": date.today().isoformat(),
        "expected_yield": result["expected_yield_kg"],
        "confidence": None,
        "model_name": "YieldPredictionStub",
        "model_version": "1",
        "risk_factors": result.get("risk_factors", []),
        "agent_run_id": agent_run_id,
    }).execute()

    return result


def _build_model_adapter(agri):
    """Build the disease model adapter from PLANT_DISEASE_PROVIDER config.

    pddd → PDDD PyTorch MobileNet checkpoint (paths resolved against repo root).
    roboflow → Roboflow hosted API.
    auto/anything else → static demo adapter.
    Falls back to the static adapter if the selected provider cannot load.
    """
    settings = get_settings()
    provider = (settings.PLANT_DISEASE_PROVIDER or "auto").lower()

    if provider == "pddd":
        root = Path(__file__).resolve().parents[3]  # repo root
        agents_dir = root / "agents"
        model_path = agents_dir / settings.PDDD_MODEL_PATH
        labels_path = agents_dir / settings.PDDD_LABELS_PATH
        if not model_path.exists():
            model_path = Path(settings.PDDD_MODEL_PATH)
        if not labels_path.exists():
            labels_path = Path(settings.PDDD_LABELS_PATH)
        if model_path.exists() and labels_path.exists():
            try:
                return agri.PDDDPlantDiseaseModelAdapter(
                    str(model_path), str(labels_path)
                ), "PDDDPlantDiseaseModelAdapter"
            except Exception:
                pass  # torch missing / load failure → fall through to static

    if provider == "roboflow":
        return agri.RoboflowPlantVillageModelAdapter(), "RoboflowPlantVillageModelAdapter"

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
        "confidence_level": diag.confidence_level.value,
        "severity": diag.severity,
        "recommendation": diag.recommendation,
        "remedies": list(diag.remedies),
        "prevention": list(diag.prevention),
        "retake_image": diag.retake_image,
        "reason_labels": list(diag.reason_labels),
    }

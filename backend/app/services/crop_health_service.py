"""Crop image health + yield analysis orchestration.

Runs the DiseasePredictionAgent (writes `disease_diagnoses` + an `agent_results`
health row) and the yield prediction (writes an `agent_results` yield row +
`yield_forecasts`). Shared by the /upload router and the LangGraph orchestrator.
"""

from datetime import date

from app.agents.runtime import agents


async def run_crop_health(sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None) -> dict:
    agri = agents()["agri"]

    model = agri.StaticPlantVillageModelAdapter(label="Corn___Northern_Leaf_Blight", confidence=0.92)
    diag = agri.DiseasePredictionAgent(model_adapter=model).analyze_image(image_url, crop_hint=crop_hint)

    health_result = _health_result_from_diagnosis(diag)

    sb.table("disease_diagnoses").insert({
        "farm_id": farm_id,
        "image_upload_id": image_id,
        "predicted_crop": diag.crop,
        "predicted_disease": diag.disease,
        "is_healthy": diag.is_healthy,
        "confidence_level": diag.confidence_level.value,
        "raw_confidence": 0.92,
        "severity": diag.severity,
        "recommendation": diag.recommendation,
        "remedies": list(diag.remedies),
        "prevention": list(diag.prevention),
        "retake_image": diag.retake_image,
        "reason_labels": list(diag.reason_labels),
        "model_source": "plantvillage-static",
        "model_name": "StaticPlantVillageModelAdapter",
        "model_version": "1",
    }).execute()

    sb.table("agent_results").insert({
        "crop_image_id": image_id,
        "image_upload_id": image_id,
        "farm_id": farm_id,
        "agent_type": "health",
        "result_json": health_result,
        "model_name": "StaticPlantVillageModelAdapter",
        "model_version": "1",
    }).execute()

    return health_result


async def run_yield_analysis(sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None) -> dict:
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
    }).execute()

    return result


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

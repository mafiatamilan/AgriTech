import asyncio
from datetime import date
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase, get_supabase_admin
from app.services.notification_service import create_notification

router = APIRouter(prefix="/upload", tags=["upload"])


@router.post("/crop-image")
async def upload_crop_image(
    farm_id: str = Form(...),
    file: UploadFile = File(...),
    crop_hint: str = Form(None),
    field_id: str = Form(None),
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    # Validate farm ownership
    farm = sb.table("farms").select("farmer_id").eq("id", farm_id).execute()
    if not farm.data or farm.data[0]["farmer_id"] != current_farmer["id"]:
        raise HTTPException(status_code=404, detail="Farm not found")

    content = await file.read()
    file_path = f"{current_farmer['id']}/{farm_id}/{uuid4().hex}-{file.filename}"
    sb.storage.from_("crop-images").upload(file_path, content)
    image_url = sb.storage.from_("crop-images").get_public_url(file_path)

    resp = sb.table("crop_images").insert({
        "farm_id": farm_id,
        "field_id": field_id,
        "farmer_id": current_farmer["id"],
        "crop_hint": crop_hint,
        "image_url": image_url,
        "analysis_status": "processing",
    }).execute()
    crop_image = resp.data[0]

    asyncio.create_task(_run_analysis(crop_image["id"], farm_id, image_url, crop_hint))

    return {"id": crop_image["id"], "image_url": image_url, "analysis_status": "processing"}


async def _run_analysis(image_id: str, farm_id: str, image_url: str, crop_hint: str | None):
    sb = get_supabase_admin()
    try:
        health = await _run_disease(sb, image_id, farm_id, image_url, crop_hint)
        await _run_yield(sb, image_id, farm_id, image_url, crop_hint)

        sb.table("crop_images").update({"analysis_status": "done"}).eq("id", image_id).execute()

        if health and (health["retake_image"] or (health["diseases_detected"] and health["health_status"] != "Healthy")):
            farm = sb.table("farms").select("farmer_id").eq("id", farm_id).execute()
            if farm.data:
                title = "Retake Crop Photo" if health["retake_image"] else "Crop Health Alert"
                await create_notification(
                    sb, farm.data[0]["farmer_id"], "agent_result",
                    title, health["recommendation"] or health["health_status"], image_id,
                )
    except Exception as exc:
        sb.table("crop_images").update({
            "analysis_status": "failed",
            "failure_reason": str(exc)[:500],
        }).eq("id", image_id).execute()


async def _run_disease(sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None) -> dict:
    from app.agents.runtime import agents
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


async def _run_yield(sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None) -> dict:
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


@router.get("/{crop_image_id}/status")
async def get_analysis_status(
    crop_image_id: str,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    img_resp = sb.table("crop_images").select("*") \
        .eq("id", crop_image_id).execute()
    if not img_resp.data:
        raise HTTPException(status_code=404, detail="Image not found")

    img = img_resp.data[0]
    results = sb.table("agent_results").select("*") \
        .eq("crop_image_id", crop_image_id).execute()

    return {
        "id": img["id"],
        "analysis_status": img["analysis_status"],
        "failure_reason": img.get("failure_reason"),
        "results": results.data,
    }
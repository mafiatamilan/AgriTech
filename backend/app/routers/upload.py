import asyncio
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
    from app.services.crop_health_service import run_crop_health
    return await run_crop_health(sb, image_id, farm_id, image_url, crop_hint)


async def _run_yield(sb, image_id: str, farm_id: str, image_url: str, crop_hint: str | None) -> dict:
    from app.services.crop_health_service import run_yield_analysis
    return await run_yield_analysis(sb, image_id, farm_id, image_url, crop_hint)


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
import asyncio
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.agents.crop_health import run_crop_health
from app.agents.yield_prediction import run_yield_prediction

router = APIRouter(prefix="/upload", tags=["upload"])


@router.post("/crop-image")
async def upload_crop_image(
    farm_id: str,
    file: UploadFile = File(...),
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    content = await file.read()
    file_path = f"{current_farmer['id']}/{farm_id}/{file.filename}"

    sb.storage.from_("crop-images").upload(file_path, content)

    image_url = sb.storage.from_("crop-images").get_public_url(file_path)

    resp = sb.table("crop_images").insert({
        "farm_id": farm_id,
        "image_url": image_url,
        "analysis_status": "pending",
    }).execute()
    crop_image = resp.data[0]

    asyncio.create_task(_run_agents(crop_image["id"], farm_id, image_url))

    return {"id": crop_image["id"], "image_url": image_url, "analysis_status": "pending"}


async def _run_agents(image_id: str, farm_id: str, image_url: str):
    sb = get_supabase()
    try:
        health_result = await run_crop_health(image_url)
        sb.table("agent_results").insert({
            "crop_image_id": image_id,
            "farm_id": farm_id,
            "agent_type": "health",
            "result_json": health_result,
        }).execute()

        yield_result = await run_yield_prediction(image_url, [])
        sb.table("agent_results").insert({
            "crop_image_id": image_id,
            "farm_id": farm_id,
            "agent_type": "yield",
            "result_json": yield_result,
        }).execute()

        sb.table("crop_images").update({"analysis_status": "done"}) \
            .eq("id", image_id).execute()
    except Exception:
        sb.table("crop_images").update({"analysis_status": "failed"}) \
            .eq("id", image_id).execute()


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
        "results": results.data,
    }

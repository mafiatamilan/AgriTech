import asyncio
import httpx
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from app.core.deps import get_current_farmer
from app.core.config import get_settings
from app.db.supabase_client import get_supabase

settings = get_settings()
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

    asyncio.create_task(_dispatch_agents(crop_image["id"], farm_id, image_url))

    return {"id": crop_image["id"], "image_url": image_url, "analysis_status": "pending"}


async def _dispatch_agents(image_id: str, farm_id: str, image_url: str):
    dispatch_url = settings.AGENT_DISPATCH_URL
    callback_base = dispatch_url.rsplit("/webhooks", 1)[0] + "/webhooks/agent-result"

    agents = ["crop_health", "yield_prediction"]

    async with httpx.AsyncClient(timeout=10.0) as client:
        for agent_type in agents:
            try:
                await client.post(dispatch_url, json={
                    "crop_image_id": image_id,
                    "farm_id": farm_id,
                    "agent_type": agent_type,
                    "image_url": image_url,
                    "callback_url": callback_base,
                })
            except httpx.RequestError:
                # Fallback: run local stub if external service unreachable
                await _fallback_stub(agent_type, image_id, farm_id, image_url)


async def _fallback_stub(agent_type: str, image_id: str, farm_id: str, image_url: str):
    from app.agents.crop_health import run_crop_health
    from app.agents.yield_prediction import run_yield_prediction
    from app.db.supabase_client import get_supabase_admin

    sb = get_supabase_admin()

    try:
        if agent_type == "crop_health":
            result = await run_crop_health(image_url)
        elif agent_type == "yield_prediction":
            result = await run_yield_prediction(image_url, [])
        else:
            return

        sb.table("agent_results").insert({
            "crop_image_id": image_id,
            "farm_id": farm_id,
            "agent_type": agent_type.replace("crop_health", "health").replace("yield_prediction", "yield"),
            "result_json": result,
        }).execute()

        # Check if all agents done for this image
        results = sb.table("agent_results").select("id") \
            .eq("crop_image_id", image_id).execute()
        if len(results.data) >= 2:
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

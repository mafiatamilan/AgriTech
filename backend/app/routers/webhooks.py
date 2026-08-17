from fastapi import APIRouter, Depends
from pydantic import BaseModel
from datetime import datetime
from app.core.security import verify_agent_webhook
from app.db.supabase_client import get_supabase_admin
from app.services.notification_service import create_notification

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


class AgentResultPayload(BaseModel):
    crop_image_id: str
    farm_id: str
    agent_type: str
    result_json: dict
    status: str  # "done" | "failed"
    error: str | None = None


@router.post("/agent-result")
async def receive_agent_result(
    payload: AgentResultPayload,
    auth_info: dict = Depends(verify_agent_webhook),
):
    sb = get_supabase_admin()

    # Insert agent result
    result_resp = sb.table("agent_results").insert({
        "crop_image_id": payload.crop_image_id,
        "farm_id": payload.farm_id,
        "agent_type": payload.agent_type,
        "result_json": payload.result_json,
    }).execute()
    agent_result_id = result_resp.data[0]["id"] if result_resp.data else None

    # Update crop_images analysis_status
    image_status = "done" if payload.status == "done" else "failed"
    sb.table("crop_images").update({"analysis_status": image_status}) \
        .eq("id", payload.crop_image_id).execute()

    # Check if farmer should be alerted (disease detected, poor health, etc.)
    if payload.status == "done" and payload.agent_type == "health":
        result = payload.result_json
        diseases = result.get("diseases_detected", [])
        health_status = result.get("health_status", "healthy")
        if diseases or health_status not in ("healthy", "optimal"):
            farm_resp = sb.table("farms").select("farmer_id").eq("id", payload.farm_id).execute()
            if farm_resp.data:
                await create_notification(
                    sb,
                    farm_resp.data[0]["farmer_id"],
                    "agent_result",
                    "Crop Health Alert",
                    f"Issues detected: {', '.join(diseases) if diseases else health_status}",
                    payload.crop_image_id,
                )

    return {"received": True, "agent_result_id": agent_result_id}

import httpx
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form
from pydantic import BaseModel
from datetime import datetime
from app.core.deps import get_current_farmer
from app.core.config import get_settings
from app.db.supabase_client import get_supabase
from app.agents.chat_agent import answer as chat_answer

settings = get_settings()
router = APIRouter(prefix="/chat", tags=["chat"])


class CreateSessionRequest(BaseModel):
    farm_id: str | None = None


@router.post("/sessions")
async def create_session(
    req: CreateSessionRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    resp = sb.table("chat_sessions").insert({
        "farmer_id": current_farmer["id"],
        "farm_id": req.farm_id,
    }).execute()
    session = resp.data[0] if resp.data else {}
    return {"id": session.get("id"), "created_at": session.get("created_at")}


@router.post("/sessions/{session_id}/messages")
async def send_message(
    session_id: str,
    content: str = Form(None),
    image: UploadFile = File(None),
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    # Verify session belongs to farmer
    session_resp = sb.table("chat_sessions").select("*") \
        .eq("id", session_id).eq("farmer_id", current_farmer["id"]).execute()
    if not session_resp.data:
        raise HTTPException(status_code=404, detail="Session not found")

    session = session_resp.data[0]
    farm_id = session.get("farm_id")

    # Upload image if present
    image_url = None
    if image:
        content_bytes = await image.read()
        file_path = f"{current_farmer['id']}/{session_id}/{image.filename}"
        sb.storage.from_("crop-images").upload(file_path, content_bytes)
        image_url = sb.storage.from_("crop-images").get_public_url(file_path)

    user_text = content or ""
    if image_url:
        user_text = f"{user_text}\n[Image: {image_url}]".strip()

    # Insert user message
    sb.table("chat_messages").insert({
        "session_id": session_id,
        "role": "user",
        "content": user_text,
        "image_url": image_url,
    }).execute()

    # Gather farm context
    farm_context = {}
    if farm_id:
        readings = sb.table("sensor_readings").select("moisture_pct, recorded_at") \
            .eq("farm_id", farm_id).order("recorded_at", desc=True).limit(5).execute()
        inventory = sb.table("inventory").select("crop_name, quantity, status") \
            .eq("farm_id", farm_id).execute()
        health = sb.table("agent_results").select("result_json, created_at") \
            .eq("farm_id", farm_id).eq("agent_type", "health") \
            .order("created_at", desc=True).limit(1).execute()
        irrigation = sb.table("irrigation_decisions").select("decision, recommended_duration_minutes, created_at") \
            .eq("farm_id", farm_id).order("created_at", desc=True).limit(3).execute()
        device = sb.table("farm_devices").select("device_uid, last_signal_strength, motor_relay_state, health_status, last_seen_at") \
            .eq("farm_id", farm_id).limit(1).execute()
        weather = sb.table("weather_snapshots").select("*") \
            .eq("farm_id", farm_id).order("recorded_at", desc=True).limit(1).execute()
        disease = sb.table("disease_diagnoses").select("predicted_crop, predicted_disease, severity, recommendation") \
            .eq("farm_id", farm_id).order("created_at", desc=True).limit(1).execute()
        recommendations = sb.table("crop_plan_recommendations").select("crop, recommendation") \
            .eq("farm_id", farm_id).order("rank", desc=False).limit(3).execute()
        farm_context = {
            "recent_readings": readings.data,
            "inventory": inventory.data,
            "latest_health": health.data[0] if health.data else None,
            "recent_irrigation_decisions": irrigation.data,
            "hardware_status": device.data[0] if device.data else None,
            "latest_weather": weather.data[0] if weather.data else None,
            "latest_disease_result": disease.data[0] if disease.data else None,
            "recommendations": recommendations.data,
        }

    # Get message history
    messages = sb.table("chat_messages").select("role, content") \
        .eq("session_id", session_id).order("created_at", desc=False).limit(20).execute()

    # Get agent reply
    reply = await chat_answer(messages.data, farm_context)

    # Insert assistant message
    sb.table("chat_messages").insert({
        "session_id": session_id,
        "role": "assistant",
        "content": reply,
        "agent_context_json": farm_context,
    }).execute()

    return {"role": "assistant", "content": reply}

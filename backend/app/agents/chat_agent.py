"""
Chat Agent — OpenAI-compatible LLM backed (opencode.ai/zen/v1 or any base URL).

Falls back to a context-aware stub when no LLM is configured or the call fails,
so the chat endpoint never breaks.
"""

import httpx
from datetime import datetime, timezone

from app.core.config import get_settings
from app.core.logging_config import get_logger

logger = get_logger("app.agents.chat")


async def answer(messages: list[dict], farm_context: dict) -> str:
    settings = get_settings()
    api_key = settings.LLM_API_KEY
    base_url = settings.LLM_API_BASE_URL
    model = settings.LLM_MODEL or "mimo-v2.5-free"

    if not (api_key and base_url):
        logger.warning("LLM not configured (missing key/base_url) — using stub reply")
        return _stub_reply(messages, farm_context)

    system_prompt = _build_system_prompt(farm_context)
    llm_messages = [{"role": "system", "content": system_prompt}]
    for m in messages[-20:]:
        llm_messages.append({"role": m.get("role") or "user", "content": m.get("content") or ""})

    url = f"{base_url.rstrip('/')}/chat/completions"
    logger.info("LLM request -> %s model=%s messages=%d", url, model, len(llm_messages))
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(
                url,
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "messages": llm_messages,
                    "max_tokens": 1024,
                    "temperature": 0.3,
                },
            )
            logger.debug("LLM response status=%d", resp.status_code)
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"].strip()
            logger.info("LLM reply received (%d chars)", len(content))
            return content
    except Exception as exc:
        logger.warning("LLM call failed (%s) — using stub reply", exc)
        return _stub_reply(messages, farm_context)


def _build_system_prompt(farm_context: dict) -> str:
    now = datetime.now(timezone.utc).isoformat()
    parts = [
        "You are AgriTech's farm assistant. Answer the farmer's questions using ONLY the supplied farm data.",
        "Never invent numbers. If data is missing, say so.",
        f"Current time: {now}",
    ]

    readings = farm_context.get("recent_readings", [])
    if readings:
        latest = readings[-1]
        parts.append(f"Soil moisture (latest): {latest.get('moisture_pct')}%")

    inventory = farm_context.get("inventory", [])
    if inventory:
        crops = ", ".join(f"{i.get('crop_name')} ({i.get('quantity')}, {i.get('status')})" for i in inventory[:5])
        parts.append(f"Inventory: {crops}")

    health = farm_context.get("latest_health")
    if health and health.get("result_json"):
        r = health["result_json"]
        parts.append(f"Crop health: {r.get('health_status')} — {r.get('disease')} ({r.get('confidence_level')})")

    irrigation = farm_context.get("recent_irrigation_decisions", [])
    if irrigation:
        last = irrigation[0]
        parts.append(f"Latest irrigation decision: {last.get('decision')} ({last.get('recommended_duration_minutes')} min)")

    device = farm_context.get("hardware_status")
    if device:
        parts.append(f"Device: {device.get('device_uid')} relay={device.get('motor_relay_state')} signal={device.get('last_signal_strength')}dBm")

    weather = farm_context.get("latest_weather")
    if weather:
        parts.append(f"Weather: {weather.get('condition')}, {weather.get('avg_temp_c')}C, rain today {weather.get('rainfall_mm_today')}mm")

    disease = farm_context.get("latest_disease_result")
    if disease:
        parts.append(f"Latest diagnosis: {disease.get('predicted_disease')} on {disease.get('predicted_crop')} — {disease.get('severity')}")

    recs = farm_context.get("recommendations", [])
    if recs:
        crops = ", ".join(r.get("crop") for r in recs[:3])
        parts.append(f"Next-season recommendations: {crops}")

    return "\n".join(f"- {p}" for p in parts)


def _stub_reply(messages: list[dict], farm_context: dict) -> str:
    last_msg = messages[-1]["content"] if messages else ""
    readings = farm_context.get("recent_readings", [])
    inventory = farm_context.get("inventory", [])
    health = farm_context.get("latest_health")

    parts = []
    if readings:
        latest = readings[-1]
        parts.append(f"Soil moisture is at {latest.get('moisture_pct', 'unknown')}%")
    if inventory:
        crops = [f"{i['crop_name']} ({i['quantity']})" for i in inventory[:3]]
        parts.append(f"Current inventory: {', '.join(crops)}")
    if health:
        result = health.get("result_json", {})
        parts.append(f"Crop health: {result.get('health_status', 'unknown')}")

    context_str = ". ".join(parts) if parts else "No farm data available yet"

    return (
        f"I received your message: \"{last_msg}\"\n\n"
        f"Farm context: {context_str}.\n\n"
        f"Note: LLM not configured — this is a fallback response."
    )

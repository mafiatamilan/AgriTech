"""
Chat Agent — stub implementation.

Input:  message history + farm context
Output: assistant reply string

TODO: Replace with real LLM call using LLM_API_KEY / LLM_API_BASE_URL
"""

from datetime import datetime


async def answer(messages: list[dict], farm_context: dict) -> str:
    last_msg = messages[-1]["content"] if messages else ""

    # Build context-aware stub response
    readings = farm_context.get("recent_readings", [])
    inventory = farm_context.get("inventory", [])
    health = farm_context.get("latest_health")

    parts = []
    if readings:
        latest = readings[-1] if readings else {}
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
        f"Note: This is a stub response. Replace with real LLM integration."
    )

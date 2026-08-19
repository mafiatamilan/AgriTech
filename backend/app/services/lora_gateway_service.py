import httpx

from app.core.config import get_settings


async def get_lora_gateway_status() -> dict:
    settings = get_settings()
    url = settings.LORA_GATEWAY_STATUS_URL.strip()
    if not url:
        return {"reachable": False}

    try:
        async with httpx.AsyncClient(timeout=settings.LORA_GATEWAY_TIMEOUT_SECONDS) as client:
            response = await client.get(url)
            response.raise_for_status()
            data = response.json()
    except Exception:
        return {"reachable": False, "url": url}

    if not isinstance(data, dict):
        return {"reachable": False, "url": url}

    return {
        "reachable": True,
        "url": url,
        "device_uid": data.get("device_uid"),
        "ip": data.get("ip"),
        "last_command": data.get("last_command"),
        "last_ack": data.get("last_ack"),
        "last_ack_rssi": data.get("last_ack_rssi"),
        "last_ack_snr": data.get("last_ack_snr"),
        "last_backend_code": data.get("last_backend_code"),
        "last_backend_action": data.get("last_backend_action"),
    }

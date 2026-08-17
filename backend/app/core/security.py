import hashlib
import hmac
import time
import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.core.config import get_settings

settings = get_settings()
security_scheme = HTTPBearer()

AGENT_SECRET_HEADER = "X-Agent-Secret"
AGENT_SIGNATURE_HEADER = "X-Signature"
AGENT_TIMESTAMP_HEADER = "X-Timestamp"
TIMESTAMP_TOLERANCE_SECONDS = 300  # 5 minutes


def decode_jwt(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


async def get_current_farmer(
    credentials: HTTPAuthorizationCredentials = Depends(security_scheme),
) -> dict:
    payload = decode_jwt(credentials.credentials)
    return {"id": payload.get("sub"), "email": payload.get("email")}


async def verify_agent_webhook(
    request: Request,
    secret_attr: str = "AGENT_WEBHOOK_SECRET",
) -> dict:
    secret = getattr(settings, secret_attr, None)
    if not secret:
        raise HTTPException(status_code=500, detail="Webhook secret not configured")

    # Option 1: Simple shared-secret header
    agent_secret = request.headers.get(AGENT_SECRET_HEADER)
    if agent_secret:
        if not hmac.compare_digest(agent_secret, secret):
            raise HTTPException(status_code=401, detail="Invalid agent secret")
        return {"method": "shared_secret"}

    # Option 2: HMAC signature verification (preferred)
    signature = request.headers.get(AGENT_SIGNATURE_HEADER)
    timestamp = request.headers.get(AGENT_TIMESTAMP_HEADER)

    if not signature or not timestamp:
        raise HTTPException(status_code=401, detail="Missing signature or timestamp header")

    # Replay protection
    try:
        ts = int(timestamp)
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid timestamp")

    if abs(time.time() - ts) > TIMESTAMP_TOLERANCE_SECONDS:
        raise HTTPException(status_code=401, detail="Request timestamp expired")

    body = await request.body()
    payload_to_sign = f"{timestamp}.{body.decode('utf-8')}".encode("utf-8")
    expected = hmac.new(secret.encode("utf-8"), payload_to_sign, hashlib.sha256).hexdigest()

    if not hmac.compare_digest(signature, expected):
        raise HTTPException(status_code=401, detail="Invalid signature")

    return {"method": "hmac_signature"}


async def verify_hardware_webhook(request: Request) -> dict:
    return await verify_agent_webhook(request, secret_attr="HARDWARE_COMMAND_SECRET")

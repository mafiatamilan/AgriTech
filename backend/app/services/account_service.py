from fastapi import HTTPException

from app.models.account import UserRole


def require_account_role(sb, *, user_id: str, role: UserRole) -> None:
    table = "vendors" if role == UserRole.vendor else "farmers"
    resp = sb.table(table).select("id").eq("id", user_id).limit(1).execute()
    if not resp.data:
        account_type = "vendor" if role == UserRole.vendor else "farmer"
        raise HTTPException(
            status_code=403,
            detail=f"{account_type.title()} account is required for this action",
        )

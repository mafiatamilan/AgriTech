from supabase import create_client, Client
from app.core.config import get_settings
from app.core.logging_config import get_logger

settings = get_settings()
logger = get_logger("app.db.supabase")


# The backend verifies the Supabase JWT itself (app/core/security.py), so it
# acts as a trusted server: DB access uses the service role key, which bypasses
# RLS. (The anon key + RLS policies keyed on auth.farmer_id() would deny every
# backend query/insert because the anon key has no uid.)
def get_supabase() -> Client:
    sb = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)
    logger.debug("supabase client created (service role) for %s", settings.SUPABASE_URL)
    return sb


def get_supabase_admin() -> Client:
    sb = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)
    logger.debug("supabase admin client created for %s", settings.SUPABASE_URL)
    return sb

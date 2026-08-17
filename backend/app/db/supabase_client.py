from supabase import create_client, Client
from app.core.config import get_settings

settings = get_settings()


# The backend verifies the Supabase JWT itself (app/core/security.py), so it
# acts as a trusted server: DB access uses the service role key, which bypasses
# RLS. (The anon key + RLS policies keyed on auth.farmer_id() would deny every
# backend query/insert because the anon key has no uid.)
def get_supabase() -> Client:
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def get_supabase_admin() -> Client:
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)

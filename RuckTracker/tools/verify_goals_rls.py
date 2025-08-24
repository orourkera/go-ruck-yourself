#!/usr/bin/env python3
"""
Verify RLS behavior for custom goals tables using existing Supabase client utilities.

Usage:
  # User-scoped check (requires a valid end-user JWT)
  export USER_JWT="<jwt>"
  python RuckTracker/tools/verify_goals_rls.py

  # Admin check (uses SUPABASE_SERVICE_ROLE_KEY from env)
  python RuckTracker/tools/verify_goals_rls.py --admin

Notes:
- No mutations are performed. This script only runs SELECT queries.
- Current user_id is parsed from the USER_JWT (payload.sub) without new dependencies.
"""
import os
import sys
import json
import base64
from typing import Optional

# Reuse existing clients (no new dependencies)
try:
    from RuckTracker.supabase_client import get_supabase_client, get_supabase_admin_client
except Exception as _import_err:
    # Defer raising to main to provide a clean message without traceback noise
    get_supabase_client = None  # type: ignore
    get_supabase_admin_client = None  # type: ignore
    _DEFERRED_IMPORT_ERROR = _import_err
else:
    _DEFERRED_IMPORT_ERROR = None

TABLES = [
    "user_custom_goals",
    "user_goal_progress",
    "user_goal_notification_schedules",
    "user_goal_messages",
]


def _b64url_decode(payload: str) -> bytes:
    # Add padding if missing
    padding = '=' * ((4 - len(payload) % 4) % 4)
    return base64.urlsafe_b64decode(payload + padding)


def extract_user_id_from_jwt(jwt: str) -> Optional[str]:
    try:
        parts = jwt.split('.')
        if len(parts) < 2:
            return None
        payload_raw = parts[1]
        payload_bytes = _b64url_decode(payload_raw)
        payload = json.loads(payload_bytes.decode('utf-8'))
        # Supabase JWT typically uses 'sub' for user id
        return payload.get('sub') or payload.get('user_id')
    except Exception:
        return None


def check_user_rls(user_jwt: str) -> int:
    """Return non-zero exit code on failure; 0 on success."""
    user_id = extract_user_id_from_jwt(user_jwt)
    if not user_id:
        print("[RLS][USER] ERROR: Could not extract user_id from USER_JWT", file=sys.stderr)
        return 2

    client = get_supabase_client(user_jwt=user_jwt)
    print(f"[RLS][USER] Using user_id: {user_id}")

    all_ok = True
    for table in TABLES:
        try:
            # Expect SELECT to be restricted to the user's own rows
            resp = client.table(table).select("user_id").limit(5).execute()
            data = resp.data or []
            bad = [row for row in data if str(row.get('user_id')) != str(user_id)]
            print(f"[RLS][USER] {table}: returned {len(data)} rows; other-user rows: {len(bad)}")
            if bad:
                all_ok = False
        except Exception as e:
            print(f"[RLS][USER] ERROR selecting {table}: {e}", file=sys.stderr)
            all_ok = False

    return 0 if all_ok else 1


def check_admin_access() -> int:
    try:
        admin = get_supabase_admin_client()
    except Exception as e:
        print(f"[RLS][ADMIN] ERROR creating admin client: {e}", file=sys.stderr)
        return 3

    all_ok = True
    for table in TABLES:
        try:
            resp = admin.table(table).select("id, user_id").limit(1).execute()
            count = len(resp.data or [])
            print(f"[RLS][ADMIN] {table}: select ok; sample rows: {count}")
        except Exception as e:
            print(f"[RLS][ADMIN] ERROR selecting {table}: {e}", file=sys.stderr)
            all_ok = False
    return 0 if all_ok else 1


if __name__ == "__main__":
    # Early diagnostics for environment and imports
    if _DEFERRED_IMPORT_ERROR is not None:
        # Minimal, helpful message without stack trace
        supabase_url_set = bool(os.environ.get("SUPABASE_URL"))
        supabase_key_set = bool(os.environ.get("SUPABASE_KEY"))
        service_key_set = bool(os.environ.get("SUPABASE_SERVICE_ROLE_KEY"))
        print("[RLS] ERROR: Failed to import Supabase client.\n"
              f" - SUPABASE_URL set: {supabase_url_set}\n"
              f" - SUPABASE_KEY set: {supabase_key_set}\n"
              f" - SUPABASE_SERVICE_ROLE_KEY set: {service_key_set}\n"
              f" - Import error: {_DEFERRED_IMPORT_ERROR}", file=sys.stderr)
        sys.exit(1)

    is_admin = "--admin" in sys.argv

    try:
        if is_admin:
            sys.exit(check_admin_access())

        user_jwt = os.environ.get("USER_JWT")
        if not user_jwt:
            print("Usage: export USER_JWT=... && python RuckTracker/tools/verify_goals_rls.py", file=sys.stderr)
            sys.exit(2)

        sys.exit(check_user_rls(user_jwt))
    except SystemExit:
        raise
    except Exception as e:
        print(f"[RLS] ERROR: Unexpected failure: {e}", file=sys.stderr)
        sys.exit(1)

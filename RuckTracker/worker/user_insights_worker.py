"""
Heroku worker script to refresh user_insights for active users and optionally add LLM candidates.
Run via Heroku Scheduler nightly, and optionally every few minutes for small batches.
"""
import logging
import os
from datetime import datetime, timedelta
from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.services.user_insights_llm import refresh_user_insights_with_llm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def iter_active_users(days: int = 90, limit: int = 1000):
    sb = get_supabase_admin_client()
    since = (datetime.utcnow() - timedelta(days=days)).isoformat() + 'Z'
    # Pull in batches
    offset = 0
    batch = 200
    fetched = 0
    while fetched < limit:
        resp = (
            sb.table('user')
            .select('id,last_active_at')
            .gte('last_active_at', since)
            .order('last_active_at', desc=True)
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            break
        for r in rows:
            yield r['id']
            fetched += 1
            if fetched >= limit:
                break
        offset += batch


def main():
    sb = get_supabase_admin_client()
    do_llm = bool(os.getenv('OPENAI_API_KEY'))
    days = int(os.getenv('INSIGHTS_ACTIVE_DAYS', '90'))
    limit = int(os.getenv('INSIGHTS_MAX_USERS', '1000'))
    src = os.getenv('INSIGHTS_SOURCE', 'nightly')
    logger.info(f"[INSIGHTS] Refresh start: days={days}, limit={limit}, do_llm={do_llm}")
    count = 0
    for uid in iter_active_users(days=days, limit=limit):
        try:
            sb.rpc('upsert_user_insights', { 'u_id': uid, 'src': src }).execute()
            if do_llm:
                refresh_user_insights_with_llm(uid)
            count += 1
            if count % 50 == 0:
                logger.info(f"[INSIGHTS] Processed {count} users...")
        except Exception as e:
            logger.warning(f"[INSIGHTS] Failed refresh for {uid}: {e}")
    logger.info(f"[INSIGHTS] Refresh complete: {count} users processed")


if __name__ == '__main__':  # pragma: no cover
    main()


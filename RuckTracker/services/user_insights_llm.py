import logging
import json
import os
from typing import Optional, Dict, Any

try:
    from openai import OpenAI  # type: ignore
except Exception:  # pragma: no cover
    OpenAI = None  # type: ignore

from ..supabase_client import get_supabase_admin_client

logger = logging.getLogger(__name__)

INSIGHT_SYSTEM_PROMPT = (
    "You are an assistant that generates concise, factual insight candidates for a rucking app. "
    "Given a JSON block of user facts (totals, recency, preferences, split aggregates), "
    "produce 2-4 short, human-friendly insight candidates as JSON only."
)

INSIGHT_USER_PROMPT = (
    "Facts JSON (compact):\n"  # The caller will append JSON after this line
    "\n\nYour task: Return JSON ONLY in this schema:\n"
    "{\n  \"candidates\": [\n    {\n      \"id\": \"string\",\n      \"type\": \"consistency|pr|recency|splits|hills|time_of_day|streak|milestone|other\",\n      \"text\": \"<= 120 chars, no hashtags\",\n      \"confidence\": 0.0-1.0,\n      \"supporting_facts\": [\"short refs to facts keys\"]\n    }\n  ]\n}\n"
    "Rules: JSON only, no prose. Keep text grounded in the facts; avoid claims not derivable from input."
)


def _get_openai_client() -> Optional[Any]:  # type: ignore
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key or OpenAI is None:
        return None
    try:
        return OpenAI(api_key=api_key)
    except Exception as e:  # pragma: no cover
        logger.warning(f"[INSIGHTS_LLM] Failed to init OpenAI client: {e}")
        return None


def generate_llm_candidates(facts: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    client = _get_openai_client()
    if not client:
        logger.info("[INSIGHTS_LLM] OpenAI not configured; skipping LLM candidates")
        return None
    try:
        # Keep token footprint small
        facts_str = json.dumps(facts)[:4000]
        messages = [
            {"role": "system", "content": INSIGHT_SYSTEM_PROMPT},
            {"role": "user", "content": INSIGHT_USER_PROMPT + "\n" + facts_str},
        ]
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            temperature=0.2,
            max_tokens=350,
        )
        content = resp.choices[0].message.content or "{}"
        # Some SDKs return as list of content parts
        if isinstance(content, list):
            content = "".join([str(x) for x in content])
        # Strip code fences if present
        s = str(content).strip()
        if s.startswith("```"):
            s = s.split("\n", 1)[1]
            if s.endswith("```"):
                s = s[:-3]
        data = json.loads(s)
        # Basic validation
        cands = data.get("candidates", []) if isinstance(data, dict) else []
        if not isinstance(cands, list):
            return None
        # Clamp fields
        norm = []
        for c in cands[:4]:
            try:
                cid = str(c.get("id") or "cand")[:40]
                ctype = str(c.get("type") or "other")
                text = str(c.get("text") or "").strip()[:140]
                conf = float(c.get("confidence") or 0.5)
                conf = max(0.0, min(1.0, conf))
                supp = c.get("supporting_facts") or []
                if text:
                    norm.append({
                        "id": cid,
                        "type": ctype,
                        "text": text,
                        "confidence": conf,
                        "supporting_facts": supp if isinstance(supp, list) else []
                    })
            except Exception:
                continue
        return {"candidates": norm}
    except Exception as e:
        logger.warning(f"[INSIGHTS_LLM] LLM generation failed: {e}")
        return None


def refresh_user_insights_with_llm(user_id: str) -> bool:
    """Fetch facts (compute if needed), run LLM to add candidates, and update user_insights row."""
    try:
        supabase = get_supabase_admin_client()
        # Ensure facts exist by running upsert (facts-only)
        try:
            supabase.rpc('upsert_user_insights', { 'u_id': user_id, 'src': 'nightly' }).execute()
        except Exception as e:
            logger.info(f"[INSIGHTS_LLM] upsert_user_insights failed/ignored for {user_id}: {e}")

        resp = (
            supabase.table('user_insights')
            .select('facts')
            .eq('user_id', user_id)
            .single()
            .execute()
        )
        if not resp.data:
            logger.warning(f"[INSIGHTS_LLM] No facts for user {user_id}; skipping LLM")
            return False
        facts = resp.data.get('facts') or {}
        cands = generate_llm_candidates(facts)
        if not cands:
            return False
        upd = supabase.table('user_insights').update({ 'insights': cands, 'generated_at': 'now()' }).eq('user_id', user_id).execute()
        return bool(upd.data)
    except Exception as e:
        logger.error(f"[INSIGHTS_LLM] Failed to refresh insights for {user_id}: {e}")
        return False


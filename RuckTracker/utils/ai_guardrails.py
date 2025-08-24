"""
AI guardrails: prefiltering, allow-lists, and validators for AI goal parsing
and notification copy generation. Uses only stdlib and existing schemas.

This module should be used by services that interact with LLMs to ensure
input/output safety and alignment with our data contracts.
"""
from __future__ import annotations

import re
import string
from typing import Dict, Any, Tuple

from marshmallow import ValidationError

# Import supported constants and schemas from API layer (kept lightweight)
from ..api.schemas import (
    SUPPORTED_METRICS,
    SUPPORTED_UNITS,
    SUPPORTED_WINDOWS,
    GoalDraftSchema,
    GoalCreateSchema,
    NotificationCopySchema,
)

# --------- Allow-lists / Block-lists ---------
# Keep blocklist conservative and expand as needed
_BLOCK_TERMS = (
    # Self-harm or medical
    "suicide", "self-harm", "self harm", "kill myself", "anorexia", "bulimia",
    # Illegal / dangerous
    "illegal", "steroids", "drug", "meth", "anabolic", "weapon",
    # Hate / harassment (lightweight)
    "hate", "racist", "nazi", "terror",
)

# Allowed emojis to appear in notification copy when uses_emoji == True
_ALLOWED_EMOJIS = {
    "🔥", "💪", "🎯", "🚀", "👏", "🏁", "⭐", "🎉", "🥇", "⏱️",
}

# Max lengths for safety and platform constraints
_MAX_TITLE_LEN = 30
_MAX_BODY_LEN = 140
_MAX_GOAL_TITLE_LEN = 200


# --------- Utilities ---------
_ws_re = re.compile(r"\s+")
_ctrl_re = re.compile(r"[\u0000-\u001F\u007F]")


def _normalize_whitespace(text: str) -> str:
    return _ws_re.sub(" ", text).strip()


def _strip_control(text: str) -> str:
    return _ctrl_re.sub("", text)


def _contains_blocked_terms(text: str) -> bool:
    low = text.lower()
    return any(term in low for term in _BLOCK_TERMS)


def _has_non_ascii(text: str) -> bool:
    return any(ord(c) > 127 for c in text)


def _contains_disallowed_emoji(text: str, allow_emoji: bool) -> bool:
    if not allow_emoji:
        # If not allowed, reject if any allowed emoji present
        return any(c in _ALLOWED_EMOJIS for c in text)
    # If allowed, ensure only from our allow-list when non-ascii
    for c in text:
        if ord(c) > 127 and c not in _ALLOWED_EMOJIS:
            return True
    return False


# --------- Public API ---------

def prefilter_user_input(text: str) -> str:
    """Sanitize and prefilter raw user input before sending to LLM.

    - Strips control chars
    - Collapses whitespace
    - Rejects if blocklisted terms present
    - Rejects if input too long (bounded implicitly by service layer)
    """
    if not isinstance(text, str):
        raise ValueError("Input must be a string")
    cleaned = _normalize_whitespace(_strip_control(text))
    if _contains_blocked_terms(cleaned):
        raise ValueError("Input contains disallowed content")
    # Aggressive length sanity (service can impose tighter caps)
    if len(cleaned) < 1 or len(cleaned) > 2000:
        raise ValueError("Input length out of bounds")
    return cleaned


def validate_goal_draft_payload(data: Dict[str, Any]) -> Dict[str, Any]:
    """Validate AI-parsed goal draft against schema and basic guards."""
    try:
        draft = GoalDraftSchema().load(data)
    except ValidationError as e:
        raise ValueError(f"Invalid goal draft: {e.messages}")

    title = draft.get("title")
    if title and len(title) > _MAX_GOAL_TITLE_LEN:
        raise ValueError("Goal title too long")

    # Guard: metric/unit/window must be in allow-lists (schema already ensures)
    if draft.get("metric") not in SUPPORTED_METRICS:
        raise ValueError("Unsupported metric")
    if draft.get("unit") not in SUPPORTED_UNITS:
        raise ValueError("Unsupported unit")
    if draft.get("window") and draft.get("window") not in SUPPORTED_WINDOWS:
        raise ValueError("Unsupported window")

    # Guard: no blocked terms in free text
    free_text = " ".join(
        [str(draft.get("title") or ""), str(draft.get("description") or "")]
    )
    if _contains_blocked_terms(free_text):
        raise ValueError("Draft contains disallowed content")

    return draft


def validate_goal_create_payload(data: Dict[str, Any]) -> Dict[str, Any]:
    """Validate client-confirmed goal create payload."""
    try:
        payload = GoalCreateSchema().load(data)
    except ValidationError as e:
        raise ValueError(f"Invalid goal create payload: {e.messages}")

    title = payload.get("title")
    if title and len(title) > _MAX_GOAL_TITLE_LEN:
        raise ValueError("Goal title too long")

    # Re-run free-text guard
    free_text = " ".join(
        [str(payload.get("title") or ""), str(payload.get("description") or "")]
    )
    if _contains_blocked_terms(free_text):
        raise ValueError("Payload contains disallowed content")

    return payload


def validate_notification_copy_payload(data: Dict[str, Any]) -> Dict[str, Any]:
    """Validate AI-generated notification copy with additional guardrails."""
    try:
        copy = NotificationCopySchema().load(data)
    except ValidationError as e:
        raise ValueError(f"Invalid notification copy: {e.messages}")

    title = _normalize_whitespace(_strip_control(copy["title"]))
    body = _normalize_whitespace(_strip_control(copy["body"]))
    uses_emoji = bool(copy.get("uses_emoji"))

    if len(title) == 0 or len(title) > _MAX_TITLE_LEN:
        raise ValueError("Title length out of bounds")
    if len(body) == 0 or len(body) > _MAX_BODY_LEN:
        raise ValueError("Body length out of bounds")

    # Disallow blocked terms
    if _contains_blocked_terms(f"{title} {body}"):
        raise ValueError("Copy contains disallowed content")

    # Emoji guard
    if _contains_disallowed_emoji(title + body, allow_emoji=uses_emoji):
        raise ValueError("Copy contains disallowed emoji or symbols")

    # Return normalized copy
    copy["title"] = title
    copy["body"] = body
    return copy


__all__ = [
    "prefilter_user_input",
    "validate_goal_draft_payload",
    "validate_goal_create_payload",
    "validate_notification_copy_payload",
]

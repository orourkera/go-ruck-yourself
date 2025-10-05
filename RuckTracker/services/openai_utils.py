"""Utility helpers for working with the OpenAI Python SDK."""
from __future__ import annotations

from typing import Any, Dict

try:  # pragma: no cover - the SDK may not be installed in all environments
    from openai import BadRequestError
except Exception:  # pragma: no cover - graceful fallback when OpenAI is missing
    BadRequestError = Exception  # type: ignore


def create_chat_completion(client: Any, /, **kwargs: Dict[str, Any]):
    """Create a chat completion, handling max token parameter differences.

    Newer OpenAI models (e.g. gpt-4.1) expect ``max_completion_tokens`` while
    older models still use ``max_tokens``. This helper tries the modern
    parameter first and falls back automatically when the API complains.
    """
    # Extract any explicit max token arguments provided by callers.
    max_completion_tokens = kwargs.pop('max_completion_tokens', None)
    legacy_max_tokens = kwargs.pop('max_tokens', None)

    if max_completion_tokens is None and legacy_max_tokens is not None:
        max_completion_tokens = legacy_max_tokens

    attempt_kwargs = dict(kwargs)
    if max_completion_tokens is not None:
        attempt_kwargs['max_completion_tokens'] = max_completion_tokens

    try:
        return client.chat.completions.create(**attempt_kwargs)
    except BadRequestError as exc:
        message = getattr(exc, 'message', str(exc))
        if 'max_completion_tokens' not in message:
            raise
    except TypeError as exc:
        # Older SDKs may raise TypeError for unexpected kwargs
        if 'max_completion_tokens' not in str(exc):
            raise
    else:
        return  # Successfully returned above

    # Fall back to legacy ``max_tokens`` parameter if the modern argument is
    # not supported by the target model / SDK combination.
    fallback_kwargs = dict(kwargs)
    if legacy_max_tokens is not None:
        fallback_kwargs['max_tokens'] = legacy_max_tokens
    elif max_completion_tokens is not None:
        fallback_kwargs['max_tokens'] = max_completion_tokens

    return client.chat.completions.create(**fallback_kwargs)

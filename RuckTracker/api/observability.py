import json
import logging
from typing import Any, Dict, List

from flask import g, request
from flask_restful import Resource

from ..services.arize_observability import observe_openai_call

logger = logging.getLogger(__name__)


class LLMObservabilityResource(Resource):
    """Accepts frontend telemetry for LLM activity and forwards it to Arize."""

    def post(self):
        try:
            payload: Dict[str, Any] = request.get_json(force=True, silent=False) or {}
        except Exception as exc:  # pragma: no cover - defensive parsing
            logger.warning(f"[OBSERVABILITY] Invalid JSON payload: {exc}")
            return {"error": "invalid_json"}, 400

        model = payload.get('model')
        response = payload.get('response')
        latency_ms = payload.get('latency_ms')

        if not model or response is None or latency_ms is None:
            return {
                "error": "missing_fields",
                "required": ["model", "response", "latency_ms"],
            }, 400

        context_type = payload.get('context_type')
        session_id = payload.get('session_id')
        prompt_tokens = payload.get('prompt_tokens')
        completion_tokens = payload.get('completion_tokens')
        total_tokens = payload.get('total_tokens')
        temperature = payload.get('temperature')
        max_tokens = payload.get('max_tokens')

        messages = self._normalize_messages(payload.get('messages'), payload.get('prompt'))

        metadata = payload.get('metadata') or {}
        if not isinstance(metadata, dict):
            metadata = {'metadata_type': str(type(metadata))}

        user_id = getattr(getattr(g, 'user', None), 'id', None) or payload.get('user_id')

        try:
            observe_openai_call(
                model=model,
                messages=messages,
                response=str(response),
                latency_ms=float(latency_ms),
                user_id=user_id,
                session_id=session_id,
                context_type=context_type,
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                total_tokens=total_tokens,
                temperature=temperature,
                max_tokens=max_tokens,
                metadata=metadata,
            )
        except Exception as exc:  # pragma: no cover
            logger.error(f"[OBSERVABILITY] Failed to relay OpenAI call to Arize: {exc}")
            return {"error": "log_failed"}, 500

        return {"status": "logged"}, 200

    def _normalize_messages(self, raw_messages: Any, prompt: Any) -> List[Dict[str, str]]:
        """Ensure we always send a well-formed messages list to Arize."""
        normalized: List[Dict[str, str]] = []

        if isinstance(raw_messages, list):
            for entry in raw_messages[:10]:  # prevent unbounded payloads
                if not isinstance(entry, dict):
                    continue
                role = str(entry.get('role', 'user'))
                content = entry.get('content')
                if isinstance(content, list):
                    flattened = []
                    for item in content:
                        if isinstance(item, dict):
                            flattened.append(str(item.get('text') or item.get('content') or item))
                        else:
                            flattened.append(str(item))
                    content = "\n".join(flattened)
                elif isinstance(content, dict):
                    # Convert nested dict content to JSON string to preserve structure
                    try:
                        content = json.dumps(content, ensure_ascii=False)
                    except Exception:  # pragma: no cover
                        content = str(content)
                else:
                    content = str(content)
                normalized.append({'role': role, 'content': content})

        if not normalized:
            prompt_text = ''
            if isinstance(prompt, str):
                prompt_text = prompt
            elif isinstance(prompt, dict):
                try:
                    prompt_text = json.dumps(prompt, ensure_ascii=False)
                except Exception:  # pragma: no cover
                    prompt_text = str(prompt)
            elif prompt is not None:
                prompt_text = str(prompt)

            if prompt_text:
                normalized.append({'role': 'user', 'content': prompt_text})

        return normalized

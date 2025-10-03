"""
Arize AI Observability Integration for LLM Monitoring
Tracks all OpenAI API calls with prompt/response logging, latency, and metadata
"""
import os
import time
import logging
from typing import Dict, Any, Optional, List
from datetime import datetime
import uuid

logger = logging.getLogger(__name__)

# Safe import for Arize
try:
    from arize.pandas.logger import Client as ArizeClient
    from arize.utils.types import ModelTypes, Environments, Schema, EmbeddingColumnNames
    ARIZE_AVAILABLE = True
except ImportError:
    logger.warning("Arize SDK not available. Install with: pip install arize")
    ArizeClient = None
    ARIZE_AVAILABLE = False

class ArizeObserver:
    """
    Singleton wrapper for Arize AI observability.
    Logs LLM prompts, responses, latency, and metadata to Arize.
    """
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ArizeObserver, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return

        self.api_key = os.getenv('ARIZE_API_KEY')
        # Support both old space_key and new space_id
        self.space_id = os.getenv('ARIZE_SPACE_ID') or os.getenv('ARIZE_SPACE_KEY')
        self.enabled = os.getenv('ARIZE_ENABLED', 'false').lower() == 'true'
        self.environment = os.getenv('ARIZE_ENVIRONMENT', 'production')

        self.client = None
        if ARIZE_AVAILABLE and self.enabled and self.api_key and self.space_id:
            try:
                self.client = ArizeClient(
                    api_key=self.api_key,
                    space_id=self.space_id
                )
                logger.info(f"✅ Arize observability initialized for environment: {self.environment}")
            except Exception as e:
                logger.error(f"Failed to initialize Arize client: {e}")
                self.client = None
        elif not self.enabled:
            logger.info("Arize observability is disabled (ARIZE_ENABLED=false)")
        else:
            logger.warning("Arize observability not configured. Set ARIZE_API_KEY, ARIZE_SPACE_ID (or ARIZE_SPACE_KEY), and ARIZE_ENABLED=true")

        self._initialized = True

    def log_llm_call(
        self,
        model: str,
        prompt: str,
        response: str,
        latency_ms: float,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        prompt_tokens: Optional[int] = None,
        completion_tokens: Optional[int] = None,
        total_tokens: Optional[int] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        context_type: Optional[str] = None,  # e.g., 'ai_cheerleader', 'coaching', 'insights'
        error: Optional[str] = None,
    ) -> bool:
        """
        Log an LLM API call to Arize for observability.

        Args:
            model: Model name (e.g., 'gpt-4.1', 'gpt-5')
            prompt: The input prompt sent to the LLM
            response: The LLM's response
            latency_ms: Time taken for the API call in milliseconds
            user_id: User identifier
            session_id: Session/request identifier
            metadata: Additional metadata to log
            prompt_tokens: Number of tokens in the prompt
            completion_tokens: Number of tokens in the completion
            total_tokens: Total tokens used
            temperature: Temperature parameter used
            max_tokens: Max tokens parameter used
            context_type: Type of LLM usage (ai_cheerleader, coaching, etc.)
            error: Error message if the call failed

        Returns:
            bool: True if logged successfully, False otherwise
        """
        if not self.client or not self.enabled:
            logger.warning(f"Arize logging skipped - client: {bool(self.client)}, enabled: {self.enabled}")
            return False

        try:
            # Generate prediction ID
            prediction_id = str(uuid.uuid4())

            # Build metadata dict
            meta = {
                'model': model,
                'latency_ms': latency_ms,
                'environment': self.environment,
                'context_type': context_type or 'unknown',
                'timestamp': datetime.utcnow().isoformat(),
            }

            if temperature is not None:
                meta['temperature'] = temperature
            if max_tokens is not None:
                meta['max_tokens'] = max_tokens
            if prompt_tokens is not None:
                meta['prompt_tokens'] = prompt_tokens
            if completion_tokens is not None:
                meta['completion_tokens'] = completion_tokens
            if total_tokens is not None:
                meta['total_tokens'] = total_tokens
            if error:
                meta['error'] = error
                meta['success'] = False
            else:
                meta['success'] = True

            # Merge with additional metadata
            if metadata:
                meta.update(metadata)

            # Log to Arize using their Python SDK
            # Note: Arize uses pandas DataFrames for batch logging
            # For real-time logging, we'll use their async logging API
            import pandas as pd

            df = pd.DataFrame([{
                'prediction_id': prediction_id,
                'prediction_timestamp': int(time.time()),
                'prediction_label': response[:1000],  # Truncate response if too long
                'prompt': prompt[:5000],  # Truncate prompt if too long
                'model_version': model,
                'user_id': user_id or 'anonymous',
                'session_id': session_id or prediction_id,
                **meta
            }])

            # Log to Arize
            model_id = f'rucking-llm-{context_type}' if context_type else 'rucking-llm'
            model_version = model

            # Define schema for Arize
            schema = Schema(
                prediction_id_column_name='prediction_id',
                timestamp_column_name='prediction_timestamp',
                prediction_label_column_name='prediction_label',
                feature_column_names=['prompt', 'model_version', 'user_id', 'session_id'] + list(meta.keys())
            )

            response = self.client.log(
                dataframe=df,
                model_id=model_id,
                model_version=model_version,
                model_type=ModelTypes.GENERATIVE_LLM,
                environment=Environments.PRODUCTION if self.environment == 'production' else Environments.TRAINING,
                schema=schema,
            )

            if response.status_code == 200:
                logger.info(f"✅ Logged LLM call to Arize: {context_type} / {model}")
                return True
            else:
                logger.error(f"Failed to log to Arize: {response.status_code} - {response.text}")
                return False

        except Exception as e:
            logger.error(f"Error logging to Arize: {e}", exc_info=True)
            return False

    def log_llm_streaming_call(
        self,
        model: str,
        prompt: str,
        full_response: str,
        latency_ms: float,
        chunk_count: int,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        context_type: Optional[str] = None,
    ) -> bool:
        """
        Log a streaming LLM call to Arize.
        Similar to log_llm_call but includes streaming-specific metadata.
        """
        streaming_metadata = {
            'streaming': True,
            'chunk_count': chunk_count,
            **(metadata or {})
        }

        return self.log_llm_call(
            model=model,
            prompt=prompt,
            response=full_response,
            latency_ms=latency_ms,
            user_id=user_id,
            session_id=session_id,
            metadata=streaming_metadata,
            context_type=context_type,
        )


# Global singleton instance
arize_observer = ArizeObserver()


def observe_openai_call(
    model: str,
    messages: List[Dict[str, str]],
    response: str,
    latency_ms: float,
    user_id: Optional[str] = None,
    session_id: Optional[str] = None,
    context_type: Optional[str] = None,
    **kwargs
) -> None:
    """
    Convenience function to log an OpenAI API call.

    Args:
        model: OpenAI model name
        messages: List of message dicts (system, user, assistant)
        response: The response from OpenAI
        latency_ms: Latency in milliseconds
        user_id: User ID
        session_id: Session ID
        context_type: Type of usage (ai_cheerleader, coaching, etc.)
        **kwargs: Additional metadata (prompt_tokens, completion_tokens, etc.)
    """
    # Combine messages into a single prompt string
    prompt = "\n\n".join([f"{msg['role']}: {msg['content']}" for msg in messages])

    arize_observer.log_llm_call(
        model=model,
        prompt=prompt,
        response=response,
        latency_ms=latency_ms,
        user_id=user_id,
        session_id=session_id,
        context_type=context_type,
        **kwargs
    )

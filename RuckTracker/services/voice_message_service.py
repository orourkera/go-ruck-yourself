"""
Voice Message Service
Handles text-to-speech conversion using ElevenLabs API and storage in Supabase
"""
import os
import logging
import uuid
import requests
from typing import Optional
from RuckTracker.supabase_client import get_supabase_admin_client

logger = logging.getLogger(__name__)

ELEVENLABS_API_KEY = os.getenv('ELEVENLABS_API_KEY')
ELEVENLABS_API_URL = 'https://api.elevenlabs.io/v1'
PLACEHOLDER_VOICE_ID = 'DEFAULT_VOICE_ID'

# Voice mappings - match AI cheerleader personalities
# TODO: Replace with your actual ElevenLabs voice IDs
VOICE_MAPPINGS = {
    'supportive_friend': os.getenv('ELEVENLABS_VOICE_SUPPORTIVE_FRIEND', PLACEHOLDER_VOICE_ID),
    'drill_sergeant': os.getenv('ELEVENLABS_VOICE_DRILL_SERGEANT', PLACEHOLDER_VOICE_ID),
    'southern_redneck': os.getenv('ELEVENLABS_VOICE_SOUTHERN_REDNECK', PLACEHOLDER_VOICE_ID),
    'yoga_instructor': os.getenv('ELEVENLABS_VOICE_YOGA_INSTRUCTOR', PLACEHOLDER_VOICE_ID),
    'british_butler': os.getenv('ELEVENLABS_VOICE_BRITISH_BUTLER', PLACEHOLDER_VOICE_ID),
    'sports_commentator': os.getenv('ELEVENLABS_VOICE_SPORTS_COMMENTATOR', PLACEHOLDER_VOICE_ID),
    'cowboy': os.getenv('ELEVENLABS_VOICE_COWBOY', PLACEHOLDER_VOICE_ID),
    'nature_lover': os.getenv('ELEVENLABS_VOICE_NATURE_LOVER', PLACEHOLDER_VOICE_ID),
    'burt_reynolds': os.getenv('ELEVENLABS_VOICE_BURT_REYNOLDS', PLACEHOLDER_VOICE_ID),
    'tom_selleck': os.getenv('ELEVENLABS_VOICE_TOM_SELLECK', PLACEHOLDER_VOICE_ID),
}

class VoiceMessageService:
    """Service for generating voice messages and uploading to storage"""

    def __init__(self):
        if not ELEVENLABS_API_KEY:
            logger.warning("ElevenLabs API key not configured - voice messages will be disabled")

    def generate_voice_message(self, message: str, voice_id: str = 'supportive_friend') -> Optional[str]:
        """
        Generate audio from text using ElevenLabs and upload to Supabase storage

        Args:
            message: Text to convert to speech (max 200 chars)
            voice_id: Voice personality ('drill_sergeant', 'supportive_friend', etc.)

        Returns:
            Public URL to audio file, or None if generation fails
        """
        try:
            if not ELEVENLABS_API_KEY:
                logger.error("ElevenLabs API key not configured")
                return None

            # Validate message length
            if len(message) > 200:
                logger.warning(f"Message too long ({len(message)} chars), truncating to 200")
                message = message[:200]

            if len(message) == 0:
                logger.error("Empty message provided")
                return None

            # Get ElevenLabs voice ID
            elevenlabs_voice = self._resolve_voice_id(voice_id)

            if not elevenlabs_voice:
                logger.warning(
                    "Voice mapping for '%s' is not configured; skipping voice generation",
                    voice_id,
                )
                return None

            logger.info(f"Generating voice message: '{message[:50]}...' with voice: {voice_id}")

            # Call ElevenLabs text-to-speech API
            response = requests.post(
                f'{ELEVENLABS_API_URL}/text-to-speech/{elevenlabs_voice}',
                headers={
                    'xi-api-key': ELEVENLABS_API_KEY,
                    'Content-Type': 'application/json'
                },
                json={
                    'text': message,
                    'model_id': 'eleven_monolingual_v1',
                    'voice_settings': {
                        'stability': 0.5,
                        'similarity_boost': 0.75,
                        'style': 0.0,
                        'use_speaker_boost': True
                    }
                },
                timeout=30
            )

            if response.status_code != 200:
                logger.error(f"ElevenLabs API error: {response.status_code} - {response.text}")
                return None

            audio_data = response.content
            logger.info(f"Generated audio: {len(audio_data)} bytes")

            # Upload to Supabase storage
            audio_url = self._upload_to_storage(audio_data, voice_id)

            if audio_url:
                logger.info(f"Voice message uploaded successfully: {audio_url}")
            else:
                logger.error("Failed to upload voice message to storage")

            return audio_url

        except requests.exceptions.Timeout:
            logger.error("ElevenLabs API timeout after 30 seconds")
            return None
        except Exception as e:
            logger.error(f"Error generating voice message: {e}", exc_info=True)
            return None

    def _upload_to_storage(self, audio_data: bytes, voice_id: str) -> Optional[str]:
        """
        Upload audio file to Supabase storage

        Args:
            audio_data: Audio bytes from ElevenLabs
            voice_id: Voice identifier for filename

        Returns:
            Public URL to uploaded file, or None if upload fails
        """
        try:
            supabase = get_supabase_admin_client()

            # Generate unique filename
            filename = f'ruck_messages/{uuid.uuid4()}_{voice_id}.mp3'

            # Upload to ruck-audio bucket
            upload_result = supabase.storage.from_('ruck-audio').upload(
                filename,
                audio_data,
                {'content-type': 'audio/mpeg'}
            )

            # Get public URL
            public_url = supabase.storage.from_('ruck-audio').get_public_url(filename)

            return public_url

        except Exception as e:
            logger.error(f"Error uploading audio to storage: {e}", exc_info=True)
            return None

    def _resolve_voice_id(self, requested_voice: str) -> Optional[str]:
        """Resolve configured ElevenLabs voice ID for the requested persona."""

        voice_key = requested_voice if requested_voice in VOICE_MAPPINGS else 'supportive_friend'
        elevenlabs_voice = VOICE_MAPPINGS.get(voice_key)

        if not elevenlabs_voice or elevenlabs_voice == PLACEHOLDER_VOICE_ID:
            logger.error(
                "ElevenLabs voice ID for '%s' is missing. Configure ELEVENLABS_VOICE_* env vars.",
                voice_key,
            )
            return None

        return elevenlabs_voice


# Singleton instance
voice_message_service = VoiceMessageService()

# Live Ruck Messaging & Following Feature

## Overview
Allow users to send messages to friends during active rucks and follow their progress in real-time.

## User Story
- When someone I follow starts rucking, I get a "X started rucking" notification
- I can tap notification to see their live progress on a map
- I can send them encouraging messages during their ruck
- They see my messages as notifications while rucking
- Rucker can enable/disable live following on a per-session basis

## Feature Components

### 1. Session Privacy Settings
**Location:** Create Session Screen

**UI Changes:**
- Add toggle: "Allow friends to follow live" (default: ON)
- Saved with session as `allow_live_following` boolean field

**Database:**
```sql
ALTER TABLE ruck_session ADD COLUMN allow_live_following BOOLEAN DEFAULT true;
```

### 2. Live Following Screen
**New Screen:** `LiveRuckFollowingScreen`

**Triggered From:**
- "X started rucking" notification → tap to view
- Following/Followers screen → "Live Now" indicator on active ruckers

**Features:**
- Real-time map showing rucker's current position
- Current stats: distance, duration, pace
- Message input at bottom
- Auto-refreshes position every 10-30 seconds

**Data Source:**
- New endpoint: `GET /api/rucks/{id}/live`
  - Returns: current location, stats, updated_at timestamp
  - Only accessible if:
    - Session has `allow_live_following = true`
    - Requesting user follows the rucker
    - Session status = 'active'

### 3. Live Ruck Messages with AI Voice
**New Feature:** In-ruck messaging system with text-to-speech via ElevenLabs

**Database Schema:**
```sql
CREATE TABLE ruck_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ruck_id INTEGER REFERENCES ruck_session(id),
  sender_id UUID REFERENCES "user"(id),
  recipient_id UUID REFERENCES "user"(id),
  message TEXT NOT NULL,
  voice_id TEXT, -- ElevenLabs voice ID (e.g., 'drill_sergeant', 'supportive_friend')
  audio_url TEXT, -- URL to generated audio file in storage
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  played_at TIMESTAMPTZ,
  CONSTRAINT valid_message_length CHECK (length(message) <= 200)
);

CREATE INDEX idx_ruck_messages_ruck_id ON ruck_messages(ruck_id);
CREATE INDEX idx_ruck_messages_recipient ON ruck_messages(recipient_id, created_at DESC);
```

**API Endpoints:**
```
POST /api/rucks/{id}/messages
  Body: {
    message: "You got this!",
    voice_id: "drill_sergeant" // optional, defaults to sender's preference
  }

  Backend Flow:
  1. Validate sender follows rucker
  2. Check session is active and allow_live_following=true
  3. Generate audio via ElevenLabs text-to-speech
  4. Upload audio to Supabase storage
  5. Save message with audio_url
  6. Send push notification to rucker

  Auth: Must follow the rucker

GET /api/rucks/{id}/messages
  Returns: All messages for this ruck (with audio_url)
  Auth: Must be rucker or follower
```

**ElevenLabs Integration:**
```python
# New service: RuckTracker/services/voice_message_service.py

import os
import requests
from RuckTracker.supabase_client import get_supabase_admin_client

ELEVENLABS_API_KEY = os.getenv('ELEVENLABS_API_KEY')

# Voice mappings (use your existing AI cheerleader voices)
VOICE_MAPPINGS = {
    'drill_sergeant': 'your-elevenlabs-voice-id-1',
    'supportive_friend': 'your-elevenlabs-voice-id-2',
    'data_nerd': 'your-elevenlabs-voice-id-3',
    'minimalist': 'your-elevenlabs-voice-id-4',
}

def generate_voice_message(message: str, voice_id: str) -> str:
    """
    Generate audio from text using ElevenLabs and upload to storage
    Returns: Public URL to audio file
    """
    # 1. Call ElevenLabs API
    elevenlabs_voice = VOICE_MAPPINGS.get(voice_id, VOICE_MAPPINGS['supportive_friend'])

    response = requests.post(
        f'https://api.elevenlabs.io/v1/text-to-speech/{elevenlabs_voice}',
        headers={'xi-api-key': ELEVENLABS_API_KEY},
        json={
            'text': message,
            'model_id': 'eleven_monolingual_v1',
            'voice_settings': {
                'stability': 0.5,
                'similarity_boost': 0.75
            }
        }
    )

    if response.status_code != 200:
        raise Exception(f'ElevenLabs API failed: {response.text}')

    # 2. Upload audio to Supabase storage
    audio_data = response.content
    filename = f'ruck_messages/{uuid.uuid4()}.mp3'

    supabase = get_supabase_admin_client()
    upload_result = supabase.storage.from_('ruck-audio').upload(
        filename,
        audio_data,
        {'content-type': 'audio/mpeg'}
    )

    # 3. Get public URL
    public_url = supabase.storage.from_('ruck-audio').get_public_url(filename)

    return public_url
```

### 4. In-Ruck Message Notifications with Audio Playback
**Notification Type:** `ruck_message`

**Backend:** `notification_manager.py`
```python
def send_ruck_message_notification(
    recipient_id: str,
    sender_name: str,
    message: str,
    ruck_id: str,
    sender_id: str,
    audio_url: str
) -> bool:
    return self.send_notification(
        recipients=[recipient_id],
        notification_type='ruck_message',
        title=f'💬 {sender_name}',
        body=message,
        data={
            'ruck_id': ruck_id,
            'sender_id': sender_id,
            'audio_url': audio_url,  # Audio file URL for playback
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        },
        sender_id=sender_id
    )
```

**Frontend:** Active Session Page
**Message Delivery:**
1. Notification arrives with `audio_url` in data
2. Auto-download and play audio immediately (no user action needed)
3. Show toast overlay: "🎤 Mike sent you a message" (with audio playing)
4. Haptic feedback on delivery
5. Audio plays through headphones if connected, speaker otherwise

**Audio Player Integration:**
```dart
// Use just_audio package for playback
class LiveMessagePlayer {
  final player = AudioPlayer();

  Future<void> playMessageAudio(String audioUrl) async {
    try {
      await player.setUrl(audioUrl);
      await player.play();

      // Optionally: Duck other audio (reduce music volume during message)
      await player.setVolume(1.0);
    } catch (e) {
      AppLogger.error('Failed to play message audio: $e');
      // Fallback: Show text notification only
    }
  }
}
```

**Settings:**
- User preference: "Auto-play voice messages" (default: ON)
- If disabled, show notification with play button instead

### 5. Following Page Live Indicators
**Location:** Following/Followers Screen

**UI Changes:**
- Show green "🔴 LIVE" badge on users with active rucks
- Tap → Navigate to `LiveRuckFollowingScreen`

**Data:**
```
GET /api/social/following
  Returns: [...existing fields..., active_ruck_id, allow_live_following]
```

## Implementation Phases

### Phase 1: Session Privacy Setting
- [ ] Add `allow_live_following` column to ruck_session table
- [ ] Add toggle to CreateSessionScreen
- [ ] Save setting when starting ruck
- [ ] Update session start API to accept this field

### Phase 2: Live Following Screen
- [ ] Create `LiveRuckFollowingScreen` widget
- [ ] Add `/api/rucks/{id}/live` endpoint
  - Auth check: must follow rucker
  - Privacy check: allow_live_following = true
  - Return current location + stats
- [ ] Implement auto-refresh (polling every 15s)
- [ ] Add map with real-time position marker
- [ ] Add current stats display

### Phase 3: Live Messaging with Voice
- [ ] Create `ruck_messages` table (with voice_id, audio_url fields)
- [ ] Create `voice_message_service.py` for ElevenLabs integration
- [ ] Create Supabase storage bucket: `ruck-audio`
- [ ] Add `/api/rucks/{id}/messages` POST endpoint (with voice generation)
- [ ] Add `/api/rucks/{id}/messages` GET endpoint
- [ ] Create message input UI in LiveRuckFollowingScreen with voice picker
- [ ] Add message list display (text + audio player)
- [ ] Implement `send_ruck_message_notification()` with audio_url

### Phase 4: In-Ruck Audio Message Playback
- [ ] Add `just_audio` package dependency
- [ ] Create `LiveMessagePlayer` service for audio playback
- [ ] Add message notification listener in ActiveSessionPage
- [ ] Auto-play audio when notification received (if enabled)
- [ ] Show toast overlay during audio playback: "🎤 [Sender] sent you a message"
- [ ] Add haptic feedback on message receipt
- [ ] Add user setting: "Auto-play voice messages" toggle
- [ ] Optional: Add "Messages" button to view/replay all during ruck

### Phase 5: Following Page Live Indicators
- [ ] Update `/api/social/following` to include active_ruck_id
- [ ] Add "LIVE" badge to FollowingScreen
- [ ] Make badge tappable → navigate to LiveRuckFollowingScreen

### Phase 6: Notification Deep Links
- [ ] Update notification handler for `ruck_started` type
- [ ] Navigate to LiveRuckFollowingScreen instead of ruck detail
- [ ] Only if session still active, else show completed ruck

## Technical Considerations

### Real-Time Updates
**Options:**
1. **Polling** (Recommended for MVP)
   - Refresh every 15-30 seconds
   - Simple, no infrastructure changes
   - Trade-off: Slight delay in updates

2. **WebSockets** (Future Enhancement)
   - True real-time updates
   - Requires WebSocket server setup
   - Better UX but more complex

**Recommendation:** Start with polling, upgrade to WebSockets if usage is high.

### Privacy & Safety
- Only followers can view live location
- Rucker can disable live following per-session
- Location updates only during active session
- Consider adding "blur start/end location" like Strava (500m privacy zone)

### Message Moderation
- 200 character limit per message
- Rate limit: 1 message per 30 seconds per ruck
- Optional: Profanity filter
- Rucker can block users (blocks messages + following)

### Battery Impact
- Polling every 15-30s is minimal impact
- Cache live endpoint responses (5-10s TTL)
- Stop polling when app backgrounded

## UI/UX Flow

### Follower Journey (Sending Voice Message):
1. Receives notification: "Sarah started rucking 🎒"
2. Taps notification → Opens LiveRuckFollowingScreen
3. Sees Sarah's current position, distance, pace on map
4. **Selects voice from dropdown:** "Drill Sergeant 🎖️"
5. Types message: "You got this! Push harder!"
6. Taps Send → Backend generates audio in Drill Sergeant voice
7. Sarah receives notification + audio auto-plays through her headphones

**Message Input UI:**
```
┌─────────────────────────────────────┐
│  Voice: [Drill Sergeant ▼]   🎤    │ ← Dropdown selector
├─────────────────────────────────────┤
│  [Type your message here...       ]│ ← Text input
│  [                              📤]│ ← Send button
└─────────────────────────────────────┘

Voice Options:
- 🎖️ Drill Sergeant (intense, motivating)
- 🤗 Supportive Friend (warm, encouraging)
- 📊 Data Nerd (analytical, stats-focused)
- 🧘 Minimalist (calm, brief)
```

**Preview Button (Optional):**
- Small speaker icon next to voice selector
- Tap to hear sample: "Keep pushing! You're doing great!"

### Rucker Journey (Receiving Voice Message):
1. Starts ruck with "Allow live following" enabled
2. Friends receive notifications
3. While rucking, receives message notification
4. **Audio auto-plays in Drill Sergeant voice:** "You got this! Push harder!"
5. Toast appears during playback: "🎤 Mike sent you a message"
6. Haptic buzz on message receipt
7. Can replay messages from "Messages" button (optional)
8. All messages saved and viewable after ruck completion

**In-Session Audio Experience:**
- Message audio plays OVER music/podcasts (audio ducking)
- Volume automatically adjusts back after message
- If headphones disconnected, plays through speaker
- Visual indicator while audio playing (animated speaker icon)

## Analytics Events
- `live_following_enabled` (on session start)
- `live_following_disabled` (on session start)
- `live_ruck_viewed` (follower opens live screen)
- `live_message_sent` (follower sends message, includes voice_id)
- `live_message_received` (rucker receives message)
- `live_message_played` (audio playback started)
- `voice_preview_played` (sender previewed voice before sending)

## Success Metrics
- % of rucks with live following enabled
- # of live views per active ruck
- # of voice messages sent per active ruck
- Most popular voice (Drill Sergeant vs Supportive Friend vs Data Nerd vs Minimalist)
- Message completion rate: % of messages that finish playing
- Engagement rate: (rucks with messages / rucks with live following)
- Conversion: % of message recipients who send messages back on their next ruck

## Cost Considerations

### ElevenLabs Pricing:
- **Free tier:** 10,000 characters/month (~50 messages)
- **Starter:** $5/month = 30,000 characters (~150 messages)
- **Creator:** $22/month = 100,000 characters (~500 messages)
- **Pro:** $99/month = 500,000 characters (~2,500 messages)

**Average message:** ~50 characters = $0.10-0.20 per message on Creator plan

**Cost Mitigation Strategies:**
1. **Cache common phrases** - Pre-generate "You got this!", "Keep going!", etc.
2. **Character limit** - 200 chars max = ~2 seconds of audio
3. **Rate limiting** - 1 message per user per ruck (or per 5 minutes)
4. **Premium feature** - Make voice messages premium-only ($4.99/month pays for itself)

**Recommendation:** Start with premium-only, monitor usage, optimize later.

## Open Questions
1. Should ruckers see a message counter during their ruck, or just notifications?
2. Allow group messaging (multiple followers chatting)?
3. Show follower count "3 friends watching" to rucker?
4. Quick reactions (👍 💪 🔥) as free alternative to voice messages?
5. Let sender record their own voice instead of TTS (more personal, no ElevenLabs cost)?

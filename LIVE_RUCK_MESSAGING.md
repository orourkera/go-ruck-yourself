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

### 3. Live Ruck Messages
**New Feature:** In-ruck messaging system

**Database Schema:**
```sql
CREATE TABLE ruck_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ruck_id INTEGER REFERENCES ruck_session(id),
  sender_id UUID REFERENCES "user"(id),
  recipient_id UUID REFERENCES "user"(id),
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  CONSTRAINT valid_message_length CHECK (length(message) <= 200)
);

CREATE INDEX idx_ruck_messages_ruck_id ON ruck_messages(ruck_id);
CREATE INDEX idx_ruck_messages_recipient ON ruck_messages(recipient_id, created_at DESC);
```

**API Endpoints:**
```
POST /api/rucks/{id}/messages
  Body: { message: "You got this!" }
  Auth: Must follow the rucker
  Validation: Session must be active, allow_live_following=true

GET /api/rucks/{id}/messages
  Returns: All messages for this ruck
  Auth: Must be rucker or follower
```

### 4. In-Ruck Message Notifications
**Notification Type:** `ruck_message`

**Backend:** `notification_manager.py`
```python
def send_ruck_message_notification(
    recipient_id: str,
    sender_name: str,
    message: str,
    ruck_id: str,
    sender_id: str
) -> bool:
    return self.send_notification(
        recipients=[recipient_id],
        notification_type='ruck_message',
        title=f'💬 {sender_name}',
        body=message,
        data={
            'ruck_id': ruck_id,
            'sender_id': sender_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        },
        sender_id=sender_id
    )
```

**Frontend:** Active Session Page
- Listen for `ruck_message` notifications while session active
- Show toast with sender name + message
- Play sound/haptic feedback

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

### Phase 3: Live Messaging
- [ ] Create `ruck_messages` table
- [ ] Add `/api/rucks/{id}/messages` POST endpoint
- [ ] Add `/api/rucks/{id}/messages` GET endpoint
- [ ] Create message input UI in LiveRuckFollowingScreen
- [ ] Add message list display
- [ ] Implement `send_ruck_message_notification()`

### Phase 4: In-Ruck Message Display
- [ ] Add message notification listener in ActiveSessionPage
- [ ] Show toast/banner when message received
- [ ] Add haptic feedback + sound
- [ ] Optional: Add "Messages" button to view all during ruck

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

### Follower Journey:
1. Receives notification: "Sarah started rucking 🎒"
2. Taps notification → Opens LiveRuckFollowingScreen
3. Sees Sarah's current position, distance, pace on map
4. Sends message: "You got this! 💪"
5. Sarah's phone vibrates with notification during ruck

### Rucker Journey:
1. Starts ruck with "Allow live following" enabled
2. Friends receive notifications
3. While rucking, receives message notification
4. Toast appears: "💬 Mike: You got this! 💪"
5. Can view all messages after completing ruck

## Analytics Events
- `live_following_enabled` (on session start)
- `live_following_disabled` (on session start)
- `live_ruck_viewed` (follower opens live screen)
- `live_message_sent` (follower sends message)
- `live_message_received` (rucker receives message)

## Success Metrics
- % of rucks with live following enabled
- # of live views per active ruck
- # of messages sent per active ruck
- Engagement rate: (rucks with messages / rucks with live following)

## Open Questions
1. Should ruckers see a message counter during their ruck, or just notifications?
2. Allow group messaging (multiple followers chatting)?
3. Show follower count "3 friends watching" to rucker?
4. Emoji-only quick reactions in addition to text messages?

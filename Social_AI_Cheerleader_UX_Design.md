# Social AI Cheerleader - UX/UI Design Document

## Overview
Transform ruck start notifications into an interactive social experience where users can view friends' live rucks and send AI-generated motivational messages.

## User Flow

### 1. Enhanced Ruck Start Notification
```
┌─────────────────────────────────────┐
│ 🎒 Sarah started rucking!           │
│ ⏱️  Started 5 minutes ago           │
│                                     │
│ [View Live Ruck] [Send Message]     │
└─────────────────────────────────────┘
```

### 2. Live Ruck Viewer Page
**Route:** `/live-ruck/:sessionId`

#### Header Section
```
┌─────────────────────────────────────┐
│ 👤 Sarah Johnson                    │
│ 🔴 LIVE • 12:34 elapsed            │
│ 📍 Centennial Park, Denver         │
└─────────────────────────────────────┘
```

#### Live Map (Privacy-Filtered)
```
┌─────────────────────────────────────┐
│                                     │
│    🗺️  Live Route Map               │
│                                     │
│    • Privacy clipped (200m radius) │
│    • Real-time position updates    │
│    • Route trail visualization     │
│                                     │
└─────────────────────────────────────┘
```

#### Stats Dashboard
```
┌───────────┬───────────┬───────────────┐
│ Distance  │   Pace    │   Duration    │
│ 2.3 mi    │ 15:30/mi  │   12:34       │
├───────────┼───────────┼───────────────┤
│ Elevation │ Heart Rate│   Calories    │
│ +127 ft   │ 145 bpm   │   287 cal     │
└───────────┴───────────┴───────────────┘
```

#### AI Message Center
```
┌─────────────────────────────────────┐
│ 🎤 Send AI Encouragement            │
│                                     │
│ Voice: [Drill Sergeant ▼]           │
│ Timing: [Send Now ▼]                │
│                                     │
│ Optional message:                   │
│ ┌─────────────────────────────────┐ │
│ │ "Keep crushing it!"             │ │
│ └─────────────────────────────────┘ │
│                                     │
│ [🎙️ Send Message] [📱 Text Only]   │
└─────────────────────────────────────┘
```

### 3. Message Timing Options
```
┌─────────────────────────────────────┐
│ When to send?                       │
│                                     │
│ ○ Send now                          │
│ ○ In 5 minutes                      │
│ ○ In 10 minutes                     │
│ ○ In 15 minutes                     │
│ ○ At next milestone                 │
│ ○ Custom: [__] minutes              │
└─────────────────────────────────────┘
```

### 4. Voice Personality Selector
```
┌─────────────────────────────────────┐
│ Choose AI Voice:                    │
│                                     │
│ 🪖 Drill Sergeant                   │
│ 🏃 Supportive Coach                 │
│ 😎 Chill Buddy                      │
│ 🔥 Hype Beast                       │
│ 👩 Lady Rucker                      │
│                                     │
│ [Preview Voice] for each option     │
└─────────────────────────────────────┘
```

## Technical Implementation

### Privacy & Security
- **Route Clipping**: Use existing `get_clipped_simplified_route()` function
- **200m Privacy Radius**: Hide start/end locations
- **Permission System**: Users must enable "Share Live Sessions"
- **Follower-Only**: Only mutual follows can view live sessions

### Real-Time Updates
- **WebSocket Connection**: Live position updates every 10-15 seconds
- **Graceful Degradation**: Fallback to polling if WebSocket fails
- **Battery Optimization**: Reduce update frequency for viewers

### Database Schema
```sql
-- New table for social AI messages
CREATE TABLE social_ai_messages (
    id SERIAL PRIMARY KEY,
    sender_id UUID REFERENCES "user"(id),
    recipient_session_id INT REFERENCES ruck_session(id),
    personality VARCHAR(50) NOT NULL,
    custom_message TEXT,
    scheduled_at TIMESTAMP,
    delivered_at TIMESTAMP,
    ai_response TEXT,
    audio_url TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Add live sharing preference to users
ALTER TABLE "user" ADD COLUMN allow_live_sharing BOOLEAN DEFAULT false;
```

### API Endpoints
```python
# Get live session data for followers
GET /api/live-ruck/:sessionId

# Send social AI message
POST /api/social-ai/send
{
    "session_id": 1234,
    "personality": "drill_sergeant", 
    "delay_minutes": 10,
    "custom_message": "You got this!"
}

# Get live session updates (WebSocket)
WS /api/live-ruck/:sessionId/updates
```

## User Experience Benefits

### For the Sender
- **Feel Connected**: Support friends in real-time
- **Gamification**: Earn "Motivator" badges
- **Personality Expression**: Choose voice that matches relationship

### For the Recipient  
- **Surprise & Delight**: Unexpected encouragement mid-ruck
- **Social Accountability**: Friends are watching and cheering
- **Motivation Boost**: AI message feels like friend sent it personally

### For the App
- **Increased Engagement**: Users check app when friends are rucking
- **Viral Growth**: "Sarah sent you motivation!" notifications
- **Premium Feature**: Advanced voices/timing options

## Edge Cases & Considerations

### Privacy Concerns
- **Opt-in Only**: Default to private sessions
- **Granular Controls**: Choose which followers can view live
- **Emergency Override**: Instantly disable sharing

### Technical Challenges
- **Battery Impact**: Minimize GPS sharing overhead
- **Network Issues**: Handle poor connectivity gracefully  
- **Spam Prevention**: Rate limit social messages

### Social Dynamics
- **Message Overload**: Max 3 social messages per session
- **Timing Conflicts**: Don't interrupt existing AI cheerleader
- **Harassment Prevention**: Block/report functionality

## Success Metrics
- **Engagement**: % of ruck start notifications that lead to live viewing
- **Social Actions**: Messages sent per live ruck viewed
- **Retention**: Users with social interactions vs without
- **Virality**: New follows generated from live ruck sharing

## Implementation Priority
1. **Phase 1**: Basic live ruck viewer (map + stats)
2. **Phase 2**: Social AI message sending
3. **Phase 3**: Advanced timing and personalization
4. **Phase 4**: Gamification and analytics

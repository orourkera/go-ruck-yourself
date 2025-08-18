# AI Cheerleader Feature Implementation Plan

## Overview
An AI-powered companion that provides real-time motivation and encouragement during ruck sessions through voice and text interactions. The cheerleader adapts to different personality modes and maintains conversation history tied to each ruck session.

## Core Features

### 1. **Multi-Modal Communication**
- **Voice Input**: Speech-to-text for user commands/responses
- **Voice Output**: Text-to-speech for AI responses with different voice profiles
- **Text Chat**: Traditional text-based conversation as fallback
- **Quick Actions**: Predefined response buttons for common interactions

### 2. **Personality Modes**
- **80s Tough Guy**: *"Come on, champ! You got this! Push through like Rocky!"*
- **Military Drill Instructor**: *"Move it, soldier! This is what separates the weak from the strong!"*
- **Gentle Encouragement**: *"You're doing wonderfully! Take your time, every step counts."*
- **Zen Master**: *"Feel the rhythm of your breath. Each step brings inner peace."*
- **Comedy Coach**: *"Why did the rucker cross the road? To get to the other stride!"*
- **Data Analyst**: *"Your pace is 12% above average. Optimal heart rate zone detected."*

### 3. **Context-Aware Responses**
- **Performance-based**: Responds to pace, distance, elevation changes
- **Time-based**: Different encouragement based on session duration
- **Weather-aware**: Acknowledges challenging conditions
- **Personal Progress**: References user's historical performance
- **Goal-oriented**: Tracks progress toward session goals

## Technical Architecture

### Frontend Components

#### 1. **AI Cheerleader Widget**
```dart
// Main widget that can be embedded in active session screen
class AICheerleaderWidget extends StatefulWidget {
  final String sessionId;
  final CheerleaderMode mode;
  final bool voiceEnabled;
}
```

#### 2. **Voice Service Integration**
```dart
class VoiceService {
  // Speech-to-text
  Future<String> transcribeAudio(File audioFile);
  
  // Text-to-speech with personality voice profiles
  Future<void> speak(String text, VoiceProfile profile);
  
  // Voice activity detection
  Stream<bool> get voiceActivityStream;
}
```

#### 3. **Conversation Manager**
```dart
class ConversationManager {
  // Send message to AI
  Future<CheerleaderResponse> sendMessage(String message, SessionContext context);
  
  // Get conversation history
  List<ConversationMessage> getSessionConversation(String sessionId);
  
  // Save conversation to local storage
  Future<void> saveConversation(String sessionId, List<ConversationMessage> messages);
}
```

### Backend Components

#### 1. **AI Service Integration**
```python
class AICheerleaderService:
    def generate_response(self, 
                         message: str, 
                         personality_mode: str,
                         session_context: SessionContext) -> CheerleaderResponse:
        """
        Generate contextual response using OpenAI API or similar
        """
        pass
    
    def get_personality_prompt(self, mode: str, context: SessionContext) -> str:
        """
        Build personality-specific system prompt
        """
        pass
```

#### 2. **Session Context Builder**
```python
class SessionContext:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.current_pace = None
        self.distance_covered = 0.0
        self.elevation_gain = 0.0
        self.duration_minutes = 0
        self.weather_conditions = None
        self.user_goals = []
        self.historical_stats = None
```

#### 3. **Conversation Storage**
```sql
-- Database schema for conversation logging
CREATE TABLE ruck_session_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES ruck_session(id),
    message_type VARCHAR(20) NOT NULL, -- 'user' or 'ai'
    content TEXT NOT NULL,
    personality_mode VARCHAR(50),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    session_context JSONB, -- Store pace, distance, etc. at time of message
    voice_enabled BOOLEAN DEFAULT FALSE
);
```

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Set up AI service integration (OpenAI API)
- [ ] Create conversation data models
- [ ] Implement basic text-based chat interface
- [ ] Design personality mode system
- [ ] Create session context extraction

### Phase 2: Voice Integration (Week 3-4)
- [ ] Integrate speech-to-text service
- [ ] Implement text-to-speech with voice profiles
- [ ] Add voice activity detection
- [ ] Create voice UI controls (push-to-talk, always listening)
- [ ] Handle voice/text mode switching

### Phase 3: Smart Responses (Week 5-6)
- [ ] Implement context-aware response generation
- [ ] Add performance-based triggers
- [ ] Create goal progress tracking
- [ ] Implement weather awareness
- [ ] Add historical performance references

### Phase 4: Polish & Integration (Week 7-8)
- [ ] Integrate with active session screen
- [ ] Add conversation history viewing
- [ ] Implement offline mode with cached responses
- [ ] Add user preference settings
- [ ] Performance optimization and testing

## User Experience Flow

### 1. **Session Start**
```
User starts ruck → AI introduces itself in selected personality mode
"Alright soldier, let's get this mission started! I'll be your drill instructor today."
```

### 2. **Mid-Session Interactions**
```
AI monitors pace/distance → Provides contextual encouragement
User: "I'm getting tired"
AI (80s mode): "Tired? Rocky didn't quit when Apollo was beating him down! You got this, champ!"
```

### 3. **Goal Achievement**
```
AI detects milestone → Celebrates achievement
"Outstanding! You just crushed your distance goal! Keep that momentum!"
```

### 4. **Session Complete**
```
AI provides session summary and motivation for next time
"Mission accomplished, soldier! 5.2 miles conquered. Your next challenge awaits."
```

## Technical Considerations

### 1. **Performance**
- Use streaming responses for real-time feel
- Cache common responses for offline scenarios
- Minimize battery impact during voice processing
- Background processing for context analysis

### 2. **Privacy**
- Local conversation storage with optional cloud sync
- Voice data processed locally when possible
- User consent for AI service usage
- Option to disable voice recording

### 3. **Accessibility**
- Voice commands for hands-free operation
- Visual indicators for voice activity
- Text alternatives for all voice interactions
- Adjustable speech rate and volume

### 4. **Personalization**
- Learning from user response patterns
- Adapting personality intensity based on feedback
- Custom trigger phrases and responses
- Integration with user goals and preferences

## Integration Points

### 1. **Active Session Screen**
- Floating chat bubble with quick access
- Voice activation button
- Personality mode selector
- Conversation history drawer

### 2. **Session Summary**
- Conversation highlights
- AI insights about performance
- Motivational message for next session

### 3. **Settings**
- Enable/disable AI cheerleader
- Select default personality mode
- Voice vs. text preferences
- Privacy and data settings

## Success Metrics

### 1. **Engagement**
- Average conversations per session
- Session completion rates with AI enabled
- User return rate after using feature

### 2. **Performance Impact**
- Improved pace consistency
- Goal achievement rates
- Session duration improvements

### 3. **User Satisfaction**
- Feature usage retention
- Personality mode preferences
- User feedback ratings

## Dependencies

### 1. **External Services**
- OpenAI API or similar AI service
- Speech-to-text service (Google/Apple/Azure)
- Text-to-speech service with multiple voices
- Weather API for context

### 2. **Flutter Packages**
- `speech_to_text` - Voice input
- `flutter_tts` - Voice output
- `permission_handler` - Microphone permissions
- `http` - API communications

### 3. **Backend Libraries**
- `openai` - AI service integration
- `sqlalchemy` - Database ORM
- `asyncio` - Async processing

## Risk Mitigation

### 1. **AI Service Costs**
- Implement response caching
- Use smaller models for common responses
- Set usage limits per user
- Offer premium tier for unlimited usage

### 2. **Voice Processing Battery Drain**
- Optimize voice detection algorithms
- Provide text-only mode
- Smart activation based on activity
- Background processing limits

### 3. **Content Appropriateness**
- Content filtering on AI responses
- Personality mode guidelines
- User reporting system
- Override mechanisms for inappropriate content

## User Experience Flow

### **Session Setup**
On the **Create Session** page:
- **AI Cheerleader toggle** - Enable/disable cheerleader for this session
- **Personality selector** - Choose from available cheerleader personalities:
  - **Motivational Coach** - Tough love, push harder messaging
  - **Supportive Friend** - Encouraging, positive reinforcement
  - **Drill Sergeant** - Military-style commands and motivation
  - **Zen Guide** - Calm, mindful, steady encouragement
  - **Southern Redneck** - "Y'all got this! Keep on truckin' like a diesel!"
  - **Dwarven Warrior** - "By my beard! March on, you have the strength of the mountain!"

### **During Ruck Audio Notifications**
The AI cheerleader will provide **real-time voice encouragement** at strategic moments:

#### **Performance Triggers**
- **Pace drops** - "Come on, pick up that pace! You've got this!"
- **Pace improves** - "That's it! You're crushing it now!"
- **Heart rate zones** - "Perfect zone, maintain that rhythm"

#### **Milestone Celebrations**
- **Split completions** - "Mile 2 down! You're 33% there!"
- **Time milestones** - "30 minutes in, feeling strong!"
- **Distance achievements** - "Halfway point! The hardest part is behind you!"

#### **Motivational Moments**
- **Session start** - "Let's do this! Time to show what you're made of!"
- **Mid-session check-ins** - "How are we feeling? Still got fight left in you!"
- **Final push** - "Last 10 minutes! Finish strong!"
- **Session complete** - "Outstanding work! That's how it's done!"

#### **Smart Timing**
- **Adaptive frequency** - More encouragement when struggling, less when crushing it
- **Context awareness** - Different messages for uphill vs flat terrain
- **Personal progress** - References to user's previous sessions and improvements

### **Implementation Notes**
- **ElevenLabs integration** for high-quality, emotional voice synthesis
- **Offline fallback** to device TTS when network unavailable  
- **User preferences** for frequency and trigger sensitivity
- **Audio mixing** with music/podcasts without interruption

This implementation plan provides a comprehensive roadmap for building an engaging, helpful AI cheerleader that enhances the rucking experience while maintaining performance and privacy standards.

---

# Detailed Implementation Guide

## Phase 1: Core Services & Models
**Checkpoint: Foundation services and data models**

### Files to Create:
```
lib/core/services/
├── ai_cheerleader_service.dart              # Main orchestration service
├── eleven_labs_service.dart                 # ElevenLabs API integration
└── audio_playback_service.dart              # Audio mixing and playback

lib/features/ai_cheerleader/
├── data/
│   ├── models/
│   │   ├── cheerleader_personality.dart     # Personality enum and data
│   │   ├── cheerleader_message.dart         # Message templates
│   │   └── cheerleader_trigger.dart         # Trigger conditions
│   └── repositories/
│       └── cheerleader_repository.dart      # Local storage for settings
├── domain/
│   ├── models/
│   │   ├── ai_cheerleader_config.dart       # User preferences model
│   │   └── cheerleader_event.dart           # Event types for triggers
│   └── services/
│       ├── message_generator_service.dart   # Generate contextual messages
│       ├── trigger_detection_service.dart   # Analyze session data for triggers
│       └── personality_service.dart         # Manage personality-specific behavior
└── presentation/
    ├── bloc/
    │   ├── ai_cheerleader_bloc.dart         # State management
    │   ├── ai_cheerleader_event.dart        # User interactions
    │   └── ai_cheerleader_state.dart        # Cheerleader states
    └── widgets/
        ├── cheerleader_toggle_widget.dart   # Enable/disable toggle
        ├── personality_selector_widget.dart # Personality dropdown
        └── cheerleader_settings_widget.dart # Volume, frequency settings
```

### Files to Modify:
- `pubspec.yaml` - Add ElevenLabs HTTP dependencies
- `lib/core/services/service_locator.dart` - Register new services

**Validation:** Services can be instantiated, personality models load correctly

---

## Phase 2: Create Session Screen Integration
**Checkpoint: UI controls for cheerleader selection**

### Files to Modify:
```
lib/features/ruck_session/presentation/screens/
└── create_session_screen.dart               # Add cheerleader controls

lib/features/ruck_session/presentation/bloc/
├── create_session_bloc.dart                 # Handle cheerleader state
├── create_session_event.dart                # Add cheerleader selection events
└── create_session_state.dart                # Include cheerleader config in state

lib/features/ruck_session/data/models/
└── session_config.dart                      # Include cheerleader settings
```

**Validation:** Create Session screen shows cheerleader toggle and personality selector, saves preferences

---

## Phase 3: ElevenLabs Integration
**Checkpoint: Voice generation working**

### Files to Modify:
```
lib/core/services/eleven_labs_service.dart   # Implement API calls
lib/core/services/audio_playback_service.dart # Handle audio streaming
```

### Environment Variables to Add:
```
.env
├── ELEVEN_LABS_API_KEY=your_key_here
└── ELEVEN_LABS_VOICE_IDS_JSON={"coach":"voice_id_1",...}
```

**Validation:** Can generate and play sample audio from ElevenLabs

---

## Phase 4: Session Trigger System
**Checkpoint: Real-time trigger detection during rucks**

### Files to Modify:
```
lib/features/ruck_session/presentation/bloc/managers/
└── location_tracking_manager.dart           # Add cheerleader triggers

lib/features/ruck_session/presentation/bloc/
├── active_session_bloc.dart                 # Integrate cheerleader events
├── active_session_event.dart                # Add trigger events
└── active_session_state.dart                # Include cheerleader status

lib/features/ai_cheerleader/domain/services/
├── trigger_detection_service.dart           # Implement pace/milestone detection
└── message_generator_service.dart           # Generate contextual messages
```

**Validation:** Triggers fire correctly during test sessions, audio plays at right moments

---

## Phase 5: Message Templates & Personality System
**Checkpoint: All 6 personalities have distinct voices and messages**

### Files to Modify:
```
lib/features/ai_cheerleader/data/models/
├── cheerleader_personality.dart             # Define all 6 personalities
└── cheerleader_message.dart                 # Templates for each personality

lib/features/ai_cheerleader/domain/services/
├── personality_service.dart                 # Personality-specific logic
└── message_generator_service.dart           # Context-aware message selection
```

### Message Template Categories:
- Session start/completion
- Milestone achievements (splits, time, distance)
- Performance triggers (pace changes, heart rate)
- Motivational check-ins
- Context-aware (terrain, weather, progress)

**Validation:** Each personality has distinct voice and messaging, appropriate for context

---

## Phase 6: Audio Management & Background Playback
**Checkpoint: Seamless audio mixing with user's music**

### Files to Modify:
```
lib/core/services/audio_playback_service.dart # Audio session management
ios/Runner/Info.plist                         # Background audio permissions
android/app/src/main/AndroidManifest.xml     # Audio focus permissions
```

### Platform-Specific Changes:
**iOS:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**Android:**
```xml
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

**Validation:** Cheerleader audio plays over music without stopping playback, proper mixing

---

## Phase 7: Settings & Preferences
**Checkpoint: User can customize cheerleader behavior**

### Files to Create:
```
lib/features/ai_cheerleader/presentation/screens/
└── cheerleader_settings_screen.dart         # Full settings page

lib/features/ai_cheerleader/presentation/widgets/
├── volume_slider_widget.dart                # Audio volume control
├── frequency_selector_widget.dart           # How often to trigger
└── trigger_sensitivity_widget.dart          # Pace drop thresholds
```

### Files to Modify:
```
lib/features/profile/presentation/screens/
└── profile_screen.dart                      # Add cheerleader settings link

lib/features/ai_cheerleader/data/repositories/
└── cheerleader_repository.dart              # Persist user preferences
```

**Validation:** Settings save/load correctly, affect cheerleader behavior in real-time

---

## Phase 8: Performance Optimization
**Checkpoint: Minimal impact on session tracking**

### Files to Modify:
```
lib/core/services/ai_cheerleader_service.dart # Add caching and rate limiting
lib/core/services/eleven_labs_service.dart    # Implement request batching
lib/features/ai_cheerleader/domain/services/
└── trigger_detection_service.dart           # Optimize trigger calculations
```

### Optimizations:
- Cache generated audio for common phrases
- Rate limit API calls to ElevenLabs
- Debounce trigger detection to prevent spam
- Background processing for non-critical operations

**Validation:** Session tracking performance unaffected, battery usage reasonable

---

## Phase 9: Error Handling & Offline Mode
**Checkpoint: Graceful fallbacks when services unavailable**

### Files to Modify:
```
lib/core/services/ai_cheerleader_service.dart # Add offline detection
lib/core/services/audio_playback_service.dart # Device TTS fallback
lib/features/ai_cheerleader/domain/services/
└── message_generator_service.dart           # Offline message templates
```

### Fallback Strategy:
- Network unavailable → Use device TTS
- ElevenLabs quota exceeded → Graceful degradation
- Audio system busy → Queue messages
- Low battery → Reduce frequency automatically

**Validation:** Cheerleader works offline with device TTS, handles API errors gracefully

---

## Phase 10: Testing & Polish
**Checkpoint: Production-ready feature**

### Files to Create:
```
test/features/ai_cheerleader/
├── ai_cheerleader_service_test.dart
├── trigger_detection_service_test.dart
├── personality_service_test.dart
└── message_generator_service_test.dart

integration_test/
└── ai_cheerleader_integration_test.dart
```

### Testing Scenarios:
- All 6 personalities produce distinct audio
- Triggers fire at correct moments during mock sessions
- Audio mixing works with various music apps
- Offline mode falls back to device TTS
- Settings persist across app restarts
- Performance impact remains minimal

**Validation:** All tests pass, feature ready for production release

---

## Implementation Checkpoints Summary:

1. ✅ **Foundation** - Services and models created
2. ✅ **UI Integration** - Create session screen updated
3. ✅ **Voice Generation** - ElevenLabs working
4. ✅ **Trigger System** - Real-time detection active
5. ✅ **Personalities** - All 6 voices distinct and contextual
6. ✅ **Audio Management** - Background playback and mixing
7. ✅ **User Settings** - Customizable preferences
8. ✅ **Performance** - Optimized for minimal impact
9. ✅ **Error Handling** - Offline mode and fallbacks
10. ✅ **Testing** - Production-ready and validated

**Estimated Timeline:** 2-3 weeks for complete implementation

---

## Integration Notes (Flutter App wiring)

These notes capture concrete wiring details used in the Flutter app so implementation remains consistent and regression-free.

### 1) Preferences (SharedPreferences)
- Key: `aiCheerleaderEnabled` (bool)
  - Default: `false` (off by default to avoid surprising users)
- Key: `aiCheerleaderPersonality` (string)
  - Default: pending canonical personality decision (see Decision Needed below)
- Key: `aiCheerleaderExplicitContent` (bool)
  - Default: `false` (clean language by default)

Naming follows existing patterns in `create_session_screen.dart` (e.g., `lastRuckWeightKg`, `lastSessionDurationMinutes`, `lastUserWeight`). No new dependencies are introduced; uses existing `shared_preferences` package.

### 2) UI: Create Session Screen
- File: `lib/features/ruck_session/presentation/screens/create_session_screen.dart`
- Add UI controls:
  - Toggle: "AI Cheerleader" → binds to `aiCheerleaderEnabled`
  - Dropdown: "Personality" → binds to `aiCheerleaderPersonality`
  - Toggle: "Explicit Content" → binds to `aiCheerleaderExplicitContent`
- Persist on change using the keys above and restore in `_loadDefaults()` alongside existing preferences.

### 3) Session Arguments
- Class: `ActiveSessionArgs` in `lib/features/ruck_session/presentation/screens/active_session_page.dart`
  - Add: `bool aiCheerleaderEnabled`
  - Add: `String? aiCheerleaderPersonality`
  - Add: `bool aiCheerleaderExplicitContent`
- Ensure these are set when navigating from Create Session to Countdown.

### 4) Bloc Event Propagation
- File: `lib/features/ruck_session/presentation/bloc/active_session_event.dart`
- Event: `SessionStarted`
  - Add named params: `bool aiCheerleaderEnabled`, `String? aiCheerleaderPersonality`, `bool aiCheerleaderExplicitContent`
  - Include them in `props`

### 5) Countdown → Start → Active Session flow
- File: `lib/features/ruck_session/presentation/screens/countdown_page.dart`
  - When dispatching `SessionStarted`, pass through `aiCheerleaderEnabled`, `aiCheerleaderPersonality`, and `aiCheerleaderExplicitContent` from `ActiveSessionArgs`.
- File: `lib/features/ruck_session/presentation/screens/active_session_page.dart`
  - All places that dispatch `SessionStarted` (initial start, retry, recovery) must include the three new fields sourced from `widget.args`.

### 6) No Mock/Hardcoded Data
- Do not hardcode personalities or sample messages in the UI. The dropdown options should reflect the canonical set defined below. All behavior should be driven by actual state (prefs, BLoCs, services), consistent with the app’s no-mock-data policy.

### 7) Canonical Personality List ✅ CHOSEN
**Selected Set B: Motivational Coach, Supportive Friend, Drill Sergeant, Zen Guide, Southern Redneck, Dwarven Warrior**

**Personality Constants:**
```dart
enum AICheerleaderPersonality {
  motivationalCoach('Motivational Coach'),
  supportiveFriend('Supportive Friend'), 
  drillSergeant('Drill Sergeant'),
  zenGuide('Zen Guide'),
  southernRedneck('Southern Redneck'),
  dwarvenWarrior('Dwarven Warrior');
  
  const AICheerleaderPersonality(this.displayName);
  final String displayName;
}
```

**Default Selection:** `supportiveFriend` (most broadly appealing, family-friendly)

**Voice/Profile Mapping:** Will be implemented with ElevenLabs voice library IDs matching each personality's tone and energy level.

---

## AI Pipeline: OpenAI + ElevenLabs + Location Context

### Technical Architecture
**Text Generation**: OpenAI GPT-3.5-turbo for creative, contextual messaging
**Voice Synthesis**: ElevenLabs for high-quality, personality-specific voices
**Location Awareness**: Reverse geocoding for location-based creative facts

### Complete Technical Flow
```
1. Trigger Detection (pace drop, milestone, etc.)
   ↓
2. Context Assembly (user data + session data + location)
   ↓  
3. OpenAI Text Generation (creative, personalized message)
   ↓
4. ElevenLabs Voice Synthesis (personality-specific audio)
   ↓
5. Audio Playback (over existing music/podcasts)
```

### OpenAI Chat Completion Payload
```json
{
  "model": "gpt-3.5-turbo",
  "messages": [
    {
      "role": "system", 
      "content": "You are a [personality] fitness coach providing 15-20 second motivational messages during ruck marches..."
    },
    {
      "role": "user",
      "content": "Generate encouragement for [user context string]"
    }
  ],
  "max_tokens": 100,
  "temperature": 0.8
}
```

### ElevenLabs Voice Synthesis Payload  
```json
{
  "text": "[OpenAI generated message]",
  "voice_id": "personality_and_gender_specific_voice_id",
  "voice_settings": {
    "stability": 0.75,
    "similarity_boost": 0.75
  }
}
```

### Message Generation Context
This comprehensive context enables deeply personalized encouragement with location awareness:

```json
{
  "trigger_type": "pace_drop|milestone|heart_rate_zone|time_checkin|completion",
  "personality": "drill_sergeant|supportive_friend|etc",
  
  // User Profile Data (from AuthBloc User model)
  "user_profile": {
    "username": "Sarah",           // Personal addressing
    "gender": "female",            // Voice selection + gendered language
    "prefer_metric": true,         // Units in messages
    "user_weight_kg": 65.0,        // Effort calculation context
    "height_cm": 165.0,            // Physical context
    "allow_ruck_sharing": true,    // Social motivation references
    "explicit_content": false,    // Language intensity level
    
    // User Experience Level & History
    "stats": {
      "total_rucks": 47,           // Experience level context
      "total_distance_km": 235.8,  // Achievement recognition
      "total_calories": 12450,     // Lifetime effort acknowledgment
      "total_power_points": 1250,  // Competitive context
      
      "this_month": {
        "rucks": 8,                // Current streak/momentum
        "distance_km": 42.1,       // Monthly progress
        "calories": 1850           // Current month effort
      }
    }
  },
  
  // Location Context (from reverse geocoding)
  "location_context": {
    "coordinates": [37.7749, -122.4194],
    "city": "San Francisco",
    "neighborhood": "Golden Gate Park", 
    "landmark": "Near Japanese Tea Garden",
    "elevation_context": "hilly_terrain",
    "historical_significance": "Olympic marathon training ground"
  },
  
  // Current Session Performance (from ActiveSessionRunning)
  "session_context": {
    "elapsed_seconds": 1800,
    "distance_km": 2.4,
    "pace": 8.5,                   // min/km or min/mile
    "calories": 245,
    "is_paused": false,
    "latest_heart_rate": 145,
    "elevation_gain": 120.0,
    "ruck_weight_kg": 20.0,
    
    // Goals & Progress
    "planned_duration_seconds": 3600,
    "planned_route_distance": 5.0,
    "progress_percentage": 48,
    "distance_remaining": 2.6,
    
    // Split/Milestone Context
    "current_split": 3,
    "splits_completed": 2,
    "last_split_pace": 8.2,
    "splits": [...],               // Full split history for this session
    
    // Terrain & Environment
    "terrain_segments": [...],     // Current terrain context
    "is_recovered_session": false  // Crashed session recovery
  }
}
```

### Experience-Based Personalization

**First-Time User (total_rucks: 0-2):**
- *"Welcome to your first ruck, Sarah! You're starting an incredible journey. Just focus on one foot in front of the other."*
- Gentle encouragement, basic technique tips
- Celebration of small milestones

**Beginner (total_rucks: 3-20):**
- *"Sarah, this is your 12th ruck - you're building real momentum! Your body is getting stronger with each step."*
- Form reminders, building confidence
- Monthly progress acknowledgment

**Intermediate (total_rucks: 21-100):**
- *"47 rucks under your belt, Sarah! You're becoming a serious rucker. That 20kg load is 30% of your body weight - warrior level!"*
- Performance comparisons, technique refinements
- Historical progress references

**Advanced (total_rucks: 100+):**
- *"Sarah, over 235km of rucking experience! You know what your body can do. Push through this wall - you've conquered harder."*
- Mental toughness, advanced strategy
- Elite performance acknowledgment

### OpenAI Generated Message Examples

**Location + Milestone Achievement:**
- *"Sarah! 2.4km through Golden Gate Park - you're rucking where Olympic marathoners train! That's ruck #48, and these hills are no joke. You're crushing it!"*

**Location + Historical Context:**
- *"Mile 2 down along the Thames! You're covering the same ground as London Marathon legends, Sarah. Those 20kg feel lighter when you're making history!"*

**Location + Effort Recognition:**
- *"Rucking through Central Park where Teddy Roosevelt used to train! At 30% body weight load, you're channeling that presidential power, Sarah!"*

**Location + Beginner Encouragement:**
- *"Sarah, Balboa Park for your 3rd ruck ever! This is where Navy SEALs trained during WWII. You're in elite company - and crushing it!"*

**Location + Advanced Challenge:**
- *"Griffith Park, ruck #127 for you Sarah! Those Hollywood Hills have seen nothing like your determination. 235km total - you're a legend in the making!"*

**Weather + Location Context:**
- *"2.4km through Pike Place in the Seattle drizzle! Real ruckers don't mind the rain - you're tougher than the Pacific Northwest weather!"*

### Privacy & Data Flow
- All user profile context stays **client-side only**
- Message generation happens locally using this rich context
- Only final generated text sent to ElevenLabs for voice synthesis
- Respects user privacy preferences (allowRuckSharing, etc.)
- No sensitive user data leaves the device

This transforms generic AI encouragement into deeply personal coaching that knows the user's name, physical capabilities, experience level, and complete ruck history.

---

## Implementation Project Plan

### Phase 1: Foundation & Setup
- [ ] **Choose canonical personality list** from the two options in the plan
- [ ] **Add OpenAI API key** to environment variables (.env file)
- [ ] **Add ElevenLabs API key** to environment variables (.env file)
- [ ] **Add dependencies** to pubspec.yaml: `dart_openai`, `http` packages

### Phase 2: Data Model Extensions
- [ ] **Extend ActiveSessionArgs class** with `aiCheerleaderEnabled` and `aiCheerleaderPersonality` fields
- [ ] **Extend SessionStarted event** with AI Cheerleader parameters and update props list
- [ ] **Add SharedPreferences persistence** for `aiCheerleaderEnabled` and `aiCheerleaderPersonality` keys

### Phase 3: UI Integration
- [ ] **Add UI controls to create_session_screen.dart**:
  - Toggle: "AI Cheerleader" → binds to `aiCheerleaderEnabled`
  - Dropdown: "Personality" → binds to `aiCheerleaderPersonality`
- [ ] **Update countdown_page.dart** to pass AI Cheerleader params in SessionStarted dispatch
- [ ] **Update active_session_page.dart** SessionStarted dispatches with AI Cheerleader params

### Phase 4: Core Services
- [ ] **Create AICheerleaderService class** for trigger detection and context assembly
- [ ] **Create OpenAIService class** for text generation with personality prompts
- [ ] **Create ElevenLabsService class** for voice synthesis with personality voices
- [ ] **Create LocationContextService** for reverse geocoding and location facts
- [ ] **Create audio playback service** that mixes cheerleader audio with user's music

### Phase 5: Integration & Triggers
- [ ] **Integrate trigger detection** in ActiveSessionBloc for:
  - Milestones (distance markers)
  - Pace drops/improvements
  - Time-based check-ins
  - Session completion
- [ ] **Add personality-specific voice ID mapping** for ElevenLabs voices
- [ ] **Add error handling and offline fallback** to device TTS

### Phase 6: Testing & Polish
- [ ] **Test end-to-end flow**: session creation → trigger → OpenAI → ElevenLabs → audio playback
- [ ] **Add user settings screen section** for AI Cheerleader frequency and volume controls
- [ ] **Performance testing** to ensure minimal impact on session tracking
- [ ] **Battery usage optimization** for background AI calls

### Phase 7: Legal & Compliance
- [ ] **Update Terms of Service** to cover AI Cheerleader feature and third-party API usage
- [ ] **Update Privacy Policy** to disclose:
  - OpenAI API usage for text generation
  - ElevenLabs API usage for voice synthesis
  - Location data usage for contextual messaging
  - Data retention policies for AI-generated content
  - User's right to disable feature at any time
- [ ] **Add in-app disclosures** when users first enable AI Cheerleader
- [ ] **COPPA compliance review** for users under 13 (if applicable)

### Dependencies Required
```yaml
dependencies:
  dart_openai: ^2.0.0
  http: ^1.1.0
  # existing shared_preferences already available
```

### Environment Variables
```env
OPENAI_API_KEY=your_openai_key_here
ELEVEN_LABS_API_KEY=your_elevenlabs_key_here
```

### Trigger Frequency & Cost Optimization

**Defined Trigger Rules:**
- **Distance Milestones**: Every 1km (0.6 miles)
- **Time Check-ins**: Every 15 minutes for sessions >30 minutes
- **Pace Changes**: Only significant changes (>15% improvement/drop lasting >2 minutes)
- **Heart Rate Zones**: Only when crossing major zones (aerobic ↔ anaerobic)
- **Session Completion**: Always triggered at end
- **Cooldown Period**: Minimum 3 minutes between any triggers

**Estimated API Calls per Session:**
- **30-minute session**: 3-5 calls (2 milestones, 1 time check, 1-2 performance, 1 completion)
- **60-minute session**: 6-10 calls (4 milestones, 2-3 time checks, 1-2 performance, 1 completion)
- **90-minute session**: 8-12 calls (6 milestones, 4 time checks, 1-2 performance, 1 completion)

**Cost Analysis:**
- OpenAI GPT-3.5-turbo: ~$0.002 per call
- ElevenLabs TTS: ~$0.0024 per call (average message ~80 characters)
- **Total per session**: $0.02-0.05 for typical 60-minute ruck
- **Monthly heavy user** (20 sessions): ~$1.00

**Battery Impact Mitigation:**
- Queue API calls when device is charging
- Reduce frequency if battery <20%
- Cache common responses for offline scenarios
- Background processing with minimal CPU usage

**Estimated Timeline**: 1-2 weeks for complete implementation
**Priority Order**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6

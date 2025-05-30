# Achievements & Recognition System - Implementation Plan

## 1. Overview & Goal

The Achievements System will provide users with recognition and motivation through milestone accomplishments in their rucking journey. This gamification feature will acknowledge various forms of progression including distance milestones, performance achievements, consistency streaks, and unique accomplishments. The system will integrate seamlessly into existing screens and provide visual feedback to enhance user engagement and retention.

## 2. Core Features

### 2.1. Achievement Categories

#### 2.1.1. Distance Milestones
- **First Steps**: Complete your first ruck (any distance)
- **Getting Started**: Complete 5km total distance
- **Marathon Equivalence**: Complete 42.2km total distance
- **Century Mark**: Complete 100km total distance
- **Distance Warrior**: Complete 500km total distance
- **Ultra Endurance**: Complete 1000km total distance

#### 2.1.2. Single Session Records
- **Pack Pioneer**: Complete a ruck with 10kg+ weight
- **Weight Warrior**: Complete a ruck with 15kg+ weight
- **Heavy Hauler**: Complete a ruck with 20kg+ weight
- **Beast Mode**: Complete a ruck with 25kg+ weight
- **Ultra Heavy**: Complete a ruck with 30kg+ weight
- **Long Hauler**: Complete a single ruck of 20km+
- **Marathon Ruck**: Complete a single ruck of 42.2km+
- **Speed Demon**: Complete a sub-6 minute/km average pace
- **Consistent Pacer**: Complete a ruck maintaining ±10% pace variation

#### 2.1.3. Power & Performance
- **Power Pioneer**: Achieve 5000+ power points (weight × distance × elevation gain)
- **Power Warrior**: Achieve 15000+ power points
- **Power Legend**: Achieve 50000+ power points
- **Hill Crusher**: Complete 500m+ elevation gain in single session
- **Mountain Mover**: Complete 1000m+ elevation gain in single session
- **Elevation Elite**: Complete 2000m+ elevation gain in single session

#### 2.1.4. Consistency & Streaks
- **Weekend Warrior**: Complete rucks on consecutive weekends (4 weeks)
- **Weekly Consistency**: Complete at least one ruck per week (8 weeks)
- **Monthly Momentum**: Complete at least 4 rucks per month (3 months)
- **Daily Dedication**: Complete rucks on consecutive days (7 days)
- **Monthly Distance**: Complete 50km+ in a single month
- **Quarterly Challenge**: Complete 200km+ in a single quarter

#### 2.1.5. Special Achievements
- **Heart Rate Hero**: Maintain target heart rate zone for 30+ minutes
- **Photo Documenter**: Upload photos to 10+ sessions
- **Social Butterfly**: Receive 50+ likes across all sessions
- **Community Supporter**: Give 100+ likes to other users
- **Weather Warrior**: Complete rucks in various weather conditions (tracked via metadata)
- **Early Bird**: Complete 5+ rucks starting before 6 AM
- **Night Owl**: Complete 5+ rucks starting after 9 PM

### 2.2. Achievement Visual Design

#### 2.2.1. Medal Tiers
- **Bronze**: Entry-level achievements (lighter accomplishments)
- **Silver**: Intermediate achievements (moderate challenge)
- **Gold**: Advanced achievements (significant accomplishment)
- **Platinum**: Elite achievements (exceptional performance)

#### 2.2.2. Achievement Graphics
- Circular medal design with app branding
- Category-specific icons (distance, weight, mountain, heart, etc.)
- Progress rings for incremental achievements
- Special animations for first-time unlocks

### 2.3. UI Integration Points

#### 2.3.1. Session Complete Screen
- **Achievement Unlock Popup**: Full-screen celebration when new achievement is earned
- **Achievement Summary**: Small cards showing recently earned achievements
- **Progress Indicators**: Show progress toward next achievements

#### 2.3.2. Ruck Buddies Screens
- **Achievement Badges**: Small medal icons next to user sessions
- **Achievement Filter**: Filter community rucks by achievement type
- **Achievement Leaderboards**: Top achievers in various categories

#### 2.3.3. Session Detail Pages
- **Achievement Section**: Dedicated area showing all achievements earned in this session
- **Achievement Sharing**: Share achievement unlocks to social media
- **Progress Context**: Show how this session contributed to achievement progress

#### 2.3.4. New Achievement Hub
- **Achievement Gallery**: Grid view of all available achievements
- **Progress Tracking**: Visual progress bars for incremental achievements
- **Statistics Dashboard**: Personal stats and achievement analytics
- **Achievement History**: Timeline of when achievements were earned

## 3. Backend Implementation

### 3.1. Database Schema Changes

#### 3.1.1. New Tables

**`achievements` Table**
```sql
CREATE TABLE achievements (
    id SERIAL PRIMARY KEY,
    achievement_key VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(50) NOT NULL,
    tier VARCHAR(20) NOT NULL, -- bronze, silver, gold, platinum
    criteria JSONB NOT NULL, -- achievement criteria and thresholds
    icon_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**`user_achievements` Table**
```sql
CREATE TABLE user_achievements (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    achievement_id INTEGER NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    session_id INTEGER REFERENCES ruck_session(id) ON DELETE SET NULL,
    earned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    progress_value NUMERIC, -- for incremental achievements
    metadata JSONB, -- additional context (e.g., specific values that triggered achievement)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, achievement_id)
);
```

**`achievement_progress` Table**
```sql
CREATE TABLE achievement_progress (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    achievement_id INTEGER NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    current_value NUMERIC DEFAULT 0,
    target_value NUMERIC NOT NULL,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB, -- context for complex progress tracking
    UNIQUE(user_id, achievement_id)
);
```

#### 3.1.2. Indexes for Performance
```sql
CREATE INDEX idx_user_achievements_user_id ON user_achievements(user_id);
CREATE INDEX idx_user_achievements_earned_at ON user_achievements(earned_at);
CREATE INDEX idx_achievement_progress_user_id ON achievement_progress(user_id);
CREATE INDEX idx_achievements_category ON achievements(category);
CREATE INDEX idx_achievements_is_active ON achievements(is_active);
```

### 3.2. API Endpoints

#### 3.2.1. Achievement Management
- `GET /api/achievements` - Get all available achievements
- `GET /api/achievements/categories` - Get achievement categories
- `GET /api/users/{user_id}/achievements` - Get user's earned achievements
- `GET /api/users/{user_id}/achievements/progress` - Get progress toward unearned achievements
- `POST /api/achievements/check/{session_id}` - Check and award achievements for a session

#### 3.2.2. Achievement Analytics
- `GET /api/achievements/leaderboard/{achievement_id}` - Get leaderboard for specific achievement
- `GET /api/achievements/stats/{user_id}` - Get achievement statistics for user
- `GET /api/achievements/recent` - Get recently earned achievements across platform

### 3.3. Achievement Calculation Logic

#### 3.3.1. Power Calculation
```python
def calculate_power_score(session):
    """Calculate power score: weight × distance × elevation_gain"""
    total_weight = session.weight_kg + session.ruck_weight_kg
    distance_km = session.distance_km or 0
    elevation_gain_m = session.elevation_gain_m or 0
    
    # Convert elevation to km for consistent units
    elevation_gain_km = elevation_gain_m / 1000
    
    power_score = total_weight * distance_km * elevation_gain_km
    return round(power_score, 2)
```

#### 3.3.2. Achievement Triggers
- **Session Completion**: Check single-session achievements
- **Daily Aggregation**: Check streak and consistency achievements
- **Real-time Updates**: Update progress counters immediately

## 4. Frontend Implementation

### 4.1. Data Models

#### 4.1.1. Achievement Model
```dart
class Achievement {
  final String id;
  final String achievementKey;
  final String name;
  final String description;
  final AchievementCategory category;
  final AchievementTier tier;
  final Map<String, dynamic> criteria;
  final String iconName;
  final bool isActive;
  final DateTime? earnedAt; // null if not earned
  final double? progressValue;
  final double? targetValue;
  
  const Achievement({
    required this.id,
    required this.achievementKey,
    required this.name,
    required this.description,
    required this.category,
    required this.tier,
    required this.criteria,
    required this.iconName,
    required this.isActive,
    this.earnedAt,
    this.progressValue,
    this.targetValue,
  });
}

enum AchievementCategory {
  distance,
  performance,
  power,
  consistency,
  social,
  special
}

enum AchievementTier {
  bronze,
  silver,
  gold,
  platinum
}
```

#### 4.1.2. Achievement Progress Model
```dart
class AchievementProgress {
  final String achievementId;
  final double currentValue;
  final double targetValue;
  final double progressPercentage;
  final DateTime lastUpdated;
  
  const AchievementProgress({
    required this.achievementId,
    required this.currentValue,
    required this.targetValue,
    required this.lastUpdated,
  });
  
  double get progressPercentage => 
    targetValue > 0 ? (currentValue / targetValue).clamp(0.0, 1.0) : 0.0;
}
```

### 4.2. State Management

#### 4.2.1. Achievement Bloc
```dart
class AchievementBloc extends Bloc<AchievementEvent, AchievementState> {
  final AchievementRepository _repository;
  
  AchievementBloc(this._repository) : super(AchievementInitial()) {
    on<LoadUserAchievements>(_onLoadUserAchievements);
    on<LoadAchievementProgress>(_onLoadAchievementProgress);
    on<CheckSessionAchievements>(_onCheckSessionAchievements);
    on<LoadAchievementLeaderboard>(_onLoadAchievementLeaderboard);
  }
}
```

### 4.3. UI Components

#### 4.3.1. Achievement Unlock Popup
```dart
class AchievementUnlockPopup extends StatelessWidget {
  final Achievement achievement;
  final VoidCallback onDismiss;
  
  // Full-screen overlay with celebration animation
  // Medal animation, confetti effect, achievement details
}
```

#### 4.3.2. Achievement Badge
```dart
class AchievementBadge extends StatelessWidget {
  final Achievement achievement;
  final double size;
  final bool showProgress;
  
  // Small circular badge for display in lists
  // Shows medal icon with tier-appropriate styling
}
```

#### 4.3.3. Achievement Progress Card
```dart
class AchievementProgressCard extends StatelessWidget {
  final Achievement achievement;
  final AchievementProgress? progress;
  
  // Card showing achievement with progress bar
  // Used in achievement hub and session complete screen
}
```

### 4.4. Screen Integration

#### 4.4.1. Session Complete Screen Updates
```dart
// Add achievement checking after session save
class SessionCompleteScreen extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return BlocListener<AchievementBloc, AchievementState>(
      listener: (context, state) {
        if (state is AchievementUnlocked) {
          _showAchievementPopup(state.achievements);
        }
      },
      child: // existing UI with achievement progress cards
    );
  }
}
```

#### 4.4.2. New Achievement Hub Screen
```dart
class AchievementHubScreen extends StatefulWidget {
  // Grid layout with filter tabs by category
  // Progress tracking for unearned achievements
  // Achievement statistics and analytics
}
```

## 5. Implementation Timeline

### Phase 1: Backend Foundation (Week 1-2)
- [ ] Create database tables and indexes
- [ ] Implement achievement calculation logic
- [ ] Create basic API endpoints
- [ ] Add achievement seed data

### Phase 2: Core Frontend (Week 3-4)
- [ ] Create data models and repositories
- [ ] Implement Achievement Bloc
- [ ] Build basic UI components
- [ ] Create achievement hub screen

### Phase 3: UI Integration (Week 5-6)
- [ ] Integrate with session complete screen
- [ ] Add achievement badges to ruck buddies
- [ ] Implement achievement unlock popups
- [ ] Add achievement progress tracking

### Phase 4: Polish & Analytics (Week 7-8)
- [ ] Achievement sharing functionality
- [ ] Leaderboard implementation
- [ ] Analytics and statistics
- [ ] Performance optimization

## 6. Testing Strategy

### 6.1. Backend Testing
- Unit tests for achievement calculation logic
- Integration tests for API endpoints
- Performance tests for achievement queries
- Test data for various achievement scenarios

### 6.2. Frontend Testing
- Widget tests for achievement components
- Integration tests for achievement flows
- User experience testing for unlock animations
- Performance testing for achievement hub

## 7. Success Metrics

### 7.1. Engagement Metrics
- Achievement unlock rate per user
- Time spent in achievement hub
- Session completion rate increase
- User retention improvement

### 7.2. Technical Metrics
- API response time for achievement queries
- Achievement calculation accuracy
- UI performance during animations
- Database query optimization

## 8. Future Enhancements

### 8.1. Social Features
- Achievement sharing to social media
- Achievement comparisons between users
- Team/group achievements
- Achievement-based challenges

### 8.2. Advanced Gamification
- Achievement point system
- Seasonal/limited-time achievements
- Achievement-based rewards
- Custom achievement creation

This implementation plan provides a comprehensive foundation for the achievements system while maintaining compatibility with the existing RuckingApp architecture and data model.

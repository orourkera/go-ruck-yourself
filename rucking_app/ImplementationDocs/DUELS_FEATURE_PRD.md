# Duels Feature - Product Requirements Document

## Executive Summary

The Duels feature introduces competitive social challenges to the Rucking app, allowing users to challenge each other across four core metrics: time, distance, elevation gain, and power points. This feature aims to increase user engagement, retention, and social interaction within the app ecosystem.

## 1. Feature Overview

### 1.1 Problem Statement
Current users lack social motivation and competitive elements to drive consistent rucking engagement. The app needs a gamification layer that encourages regular participation and builds community.

### 1.2 Solution
A peer-to-peer challenge system where users can:
- Challenge random users or specific users by email
- Compete across multiple metrics within defined timeframes
- Track real-time progress and leaderboards
- Build a competitive social network around rucking

### 1.3 Success Metrics
- **Primary**: 25% increase in weekly active sessions
- **Secondary**: 40% user participation in duels within 3 months
- **Tertiary**: 15% improvement in user retention (D30)

## 2. User Stories

### 2.1 Core User Stories
**As a competitive user, I want to:**
- Challenge other users to beat my distance/time/elevation records
- See real-time progress of ongoing duels
- Browse available public challenges
- Track my duel win/loss record
- View other participants' duel records before joining challenges

**As a social user, I want to:**
- Challenge friends by their email address
- Receive notifications when challenged or when duels end
- Share duel victories on social media
- View past duel history and achievements
- See opponents' competitive track record

**As a casual user, I want to:**
- Join public duels without commitment pressure
- Set appropriate timeframes for my schedule
- Filter duels by difficulty/type
- Opt out of random challenges

## 3. Functional Requirements

### 3.1 Duel Creation
- **Challenge Types**: Distance, Time, Elevation Gain, Power Points
- **Target Selection**: Random user OR specific email address
- **Timeframes**: 24 hours, 3 days, 1 week, 2 weeks, 1 month
- **Title**: Custom challenge title (50 character limit)
- **Location**: Creator's city and state/province (required for browsability)
- **Privacy**: Public (browsable) or Private (invite-only)

### 3.2 Duel Management
- **Accept/Decline**: Duels remain open until someone accepts them
- **Progress Tracking**: Real-time leaderboard updates
- **Session Attribution**: Automatic tracking of relevant sessions
- **Early Completion**: Option to end duel when target is reached

### 3.3 Browse & Discovery
- **Active Duels**: All ongoing public challenges
- **Filter Options**: Type, timeframe, difficulty level, location (city/state)
- **Search**: Find duels by title, creator, or location
- **Recommendations**: Suggested duels based on user performance and proximity

### 3.4 User Dashboard
- **My Active Duels**: Current challenges with progress bars
- **Opponent Progress**: Last session details and current standings
- **Past Duels**: Historical record with win/loss status
- **Statistics**: Overall duel performance metrics

## 4. Technical Requirements

### 4.1 Database Schema

#### 4.1.1 duels table
```sql
CREATE TABLE duels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(50) NOT NULL,
  challenge_type VARCHAR(20) NOT NULL CHECK (challenge_type IN ('distance', 'time', 'elevation', 'power_points')),
  target_value DECIMAL(10,2) NOT NULL,
  timeframe_hours INTEGER NOT NULL,
  creator_city VARCHAR(100) NOT NULL,
  creator_state VARCHAR(100) NOT NULL,
  is_public BOOLEAN DEFAULT true,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  starts_at TIMESTAMP WITH TIME ZONE,
  ends_at TIMESTAMP WITH TIME ZONE,
  winner_id UUID REFERENCES users(id),
  max_participants INTEGER DEFAULT 2
);
```

#### 4.1.2 duel_participants table
```sql
CREATE TABLE duel_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  duel_id UUID NOT NULL REFERENCES duels(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  current_value DECIMAL(10,2) DEFAULT 0,
  last_session_id UUID REFERENCES ruck_sessions(id),
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(duel_id, user_id)
);
```

#### 4.1.3 duel_sessions table
```sql
CREATE TABLE duel_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  duel_id UUID NOT NULL REFERENCES duels(id) ON DELETE CASCADE,
  participant_id UUID NOT NULL REFERENCES duel_participants(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES ruck_sessions(id) ON DELETE CASCADE,
  contribution_value DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(duel_id, session_id)
);
```

#### 4.1.4 duel_invitations table
```sql
CREATE TABLE duel_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  duel_id UUID NOT NULL REFERENCES duels(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  invitee_email VARCHAR(255) NOT NULL,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(duel_id, invitee_email)
);
```

#### 4.1.5 user_duel_stats table
```sql
CREATE TABLE user_duel_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  duels_created INTEGER DEFAULT 0,
  duels_joined INTEGER DEFAULT 0,
  duels_completed INTEGER DEFAULT 0,
  duels_won INTEGER DEFAULT 0,
  duels_lost INTEGER DEFAULT 0,
  duels_abandoned INTEGER DEFAULT 0,
  total_distance_challenged DECIMAL(10,2) DEFAULT 0,
  total_time_challenged INTEGER DEFAULT 0,
  total_elevation_challenged DECIMAL(10,2) DEFAULT 0,
  total_power_points_challenged INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);
```

### 4.2 API Endpoints

#### 4.2.1 Duel Management
- `POST /duels` - Create new duel
- `GET /duels` - Browse public duels (with filters: ?type=distance&timeframe=3&location=city)
- `GET /duels/my` - Get user's duels (active + past)
- `GET /duels/{id}` - Get specific duel details
- `PUT /duels/{id}/accept` - Accept duel invitation
- `PUT /duels/{id}/decline` - Decline duel invitation
- `DELETE /duels/{id}` - Cancel duel (creator only)

#### 4.2.2 Duel Progress & Sessions
- `GET /duels/{id}/participants` - Get participant progress and leaderboard
- `POST /duels/{id}/sessions` - Link session to duel (auto-called after session completion)
- `GET /duels/{id}/feed` - Get duel activity feed
- `PUT /duels/{id}/complete` - Manually complete duel (when target reached early)

#### 4.2.3 User Statistics & Invitations
- `GET /users/{id}/duel-stats` - Get user duel statistics
- `GET /users/duel-stats/bulk` - Get multiple users' duel statistics (for duel cards)
- `GET /users/me/duels/history` - Get user's duel history
- `PUT /users/me/duel-preferences` - Update duel preferences
- `POST /duels/{id}/invite` - Send email invitation for private duel

#### 4.2.4 Integration with Existing Systems
- Leverage existing `/notifications/` endpoints for duel notifications
- Integrate with existing `/rucks/{id}/complete` flow to trigger duel progress updates
- Use existing authentication and user management patterns

#### 4.2.5 Data Model Integration
**Existing Table References:**
- `users` table: Primary user authentication and profile data
- `ruck_sessions` table: Individual rucking sessions (note: singular naming)
- `notifications` table: Existing notification system with `recipient_id` field

**New Duel Tables Integration:**
- All duel tables use UUID primary keys for consistency
- Foreign key references to `users(id)` and `ruck_sessions(id)`
- Follow existing naming conventions with `created_at`/`updated_at` timestamp patterns
- Maintain referential integrity with CASCADE deletes where appropriate

### 4.3 Real-time Updates
- WebSocket connections for live progress updates
- Push notifications for duel events
- Background job processing for duel completion

## 5. User Interface & Experience

### 5.1 Navigation Changes
- **Remove**: Stats tab from main navigation
- **Add**: Duels tab in main navigation
- **Modify**: History tab to include previous Stats content

### 5.2 Duels Tab Structure
```
Duels Tab
├── Browse Duels (default view)
│   ├── Filter bar (Type, Timeframe, Difficulty)
│   ├── Search functionality
│   └── Duel cards with join buttons
├── My Active Duels
│   ├── Progress indicators
│   ├── Opponent last session details
│   └── Quick action buttons
└── Past Duels
    ├── Win/Loss record
    ├── Performance statistics
    └── Rematch options
```

### 5.3 Key UI Components

#### 5.3.1 Duel Creation Flow
1. **Challenge Type Selection**: 4 large cards for each metric type
2. **Target Setting**: Input field with suggestions based on user history
3. **Timeframe Selection**: Dropdown with predefined options
4. **Opponent Selection**: Toggle between "Random" and "Email invite"
5. **Location Selection**: Input field for creator's city and state/province
6. **Privacy Settings**: Public/Private toggle
7. **Title Input**: Optional custom title with character limit

#### 5.3.2 Duel Card Component
- **Header**: Title, challenge type icon, timeframe
- **Creator Info**: Name, location, and duel record (W-L-C format)
- **Progress Bar**: Visual representation of completion
- **Participants**: Avatars, current standings, and participant records
- **Actions**: Join, View Details, Share buttons
- **Status Indicator**: Active, Pending, Completed badges

#### 5.3.3 Active Duel Dashboard
- **Hero Section**: Current position and progress
- **Opponent Panel**: Last session details and current value
- **Recent Activity**: Feed of participant sessions
- **Quick Actions**: View leaderboard, add session

## 6. Notification System

### 6.1 Integration with Existing System
- Leverage existing `notifications` table (with `recipient_id` field)
- Use existing `/notifications/` endpoints:
  - `GET /notifications/` - Get user notifications
  - `POST /notifications/{id}/read` - Mark notification as read
  - `POST /notifications/read-all` - Mark all notifications as read

### 6.2 Duel Notification Types
- **Duel Invitation**: When challenged by another user
- **Duel Accepted**: When invitation is accepted
- **Progress Update**: When opponent completes a session
- **Position Change**: When leaderboard position changes
- **Duel Completion**: When duel ends with results
- **Duel Reminder**: 24 hours before duel expires

### 6.3 Notification Channels
- **Push Notifications**: Critical events (invitations, completions)
- **In-App Notifications**: Progress updates and reminders via existing notification system
- **Email Notifications**: Weekly duel summary (optional)

## 7. Business Considerations

### 7.1 Monetization Opportunities
- **Premium Duels**: Advanced challenge types for Pro users
- **Unlimited Duels**: Free users limited to 3 active duels
- **Custom Timeframes**: Pro feature for non-standard durations
- **Duel Analytics**: Detailed performance insights for Pro users

### 7.2 Community Guidelines
- **Fair Play**: Rules against session manipulation
- **Reporting System**: For inappropriate duel titles or behavior
- **Moderation Tools**: Admin controls for duel management
- **Privacy Protection**: Anonymous random matching option

## 8. Implementation Plan

### 8.1 Phase 1: Core Infrastructure (Weeks 1-3)
- Database schema implementation
- Basic API endpoints
- Navigation restructuring (Stats → History, new Duels tab)

### 8.2 Phase 2: Duel Creation & Management (Weeks 4-6)
- Duel creation flow
- Invitation system
- Basic duel dashboard

### 8.3 Phase 3: Real-time Features (Weeks 7-9)
- Progress tracking
- Live leaderboards
- WebSocket implementation

### 8.4 Phase 4: Discovery & Social (Weeks 10-12)
- Browse duels functionality
- Search and filtering
- Social sharing features

### 8.5 Phase 5: Polish & Premium (Weeks 13-15)
- Notification system
- Premium features
- Analytics and insights

## 9. Risk Analysis

### 9.1 Technical Risks
- **Real-time Performance**: WebSocket scaling challenges
- **Data Consistency**: Race conditions in progress updates
- **Migration Complexity**: Moving Stats tab content to History

**Mitigation**: Implement caching layers, use database transactions, phased rollout

### 9.2 Product Risks
- **Low Adoption**: Users may not engage with competitive features
- **Cheating**: Potential for GPS/session manipulation
- **Toxicity**: Negative competitive behavior

**Mitigation**: Soft launch with beta users, implement anti-cheat measures, strong community guidelines

### 9.3 Business Risks
- **Development Timeline**: Complex feature may delay other priorities
- **User Confusion**: Navigation changes may disorient existing users
- **Support Overhead**: New feature may increase support requests

**Mitigation**: Clear communication about changes, comprehensive help documentation, staged rollout

## 10. Success Metrics & KPIs

### 10.1 Engagement Metrics
- **Duel Participation Rate**: % of users who join at least one duel
- **Active Duels per User**: Average number of concurrent duels
- **Completion Rate**: % of accepted duels that reach completion
- **Session Attribution**: % of sessions linked to active duels

### 10.2 Retention Metrics
- **Duel User Retention**: D7, D30 retention for users who participate in duels
- **Session Frequency**: Change in session frequency for duel participants
- **Feature Stickiness**: % of users who return to duels after first experience

### 10.3 Social Metrics
- **Invitation Rate**: Average invitations sent per user
- **Friend Challenges**: % of duels between connected users
- **Viral Coefficient**: New users acquired through duel invitations

## 11. Future Enhancements

### 11.1 Advanced Features
- **Team Duels**: Multi-person team competitions
- **Tournament Mode**: Bracket-style elimination tournaments
- **Seasonal Challenges**: App-wide competitive events
- **Achievement System**: Badges for duel milestones

### 11.2 Integration Opportunities
- **Social Media**: Share duel victories on Instagram/Twitter
- **Wearable Devices**: Real-time progress from fitness trackers
- **Location-based**: Duels specific to geographic regions
- **Corporate Challenges**: Team-building features for companies

This comprehensive PRD provides the foundation for implementing a competitive social layer that will transform the Rucking app from a solo fitness tracker into an engaging community platform.

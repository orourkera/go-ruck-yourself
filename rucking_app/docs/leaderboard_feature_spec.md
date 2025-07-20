# Ruck Leaderboard Feature Specification

## Overview
A real-time leaderboard that displays public ruck statistics for all users, replacing the current Duels page. The leaderboard will showcase competitive metrics with smooth animations and real-time updates.

## User Experience

### Navigation
- **Entry Point**: Tap the Duels icon in the bottom navigation
- **Replaces**: Current Duels page functionality
- **Icon**: Keep existing duels icon but redirect to leaderboard

### Page Layout

#### Header
```
🏆 RUCK LEADERBOARD
[Sort Dropdown] [Filter Icon] [Refresh Icon]
```

#### Leaderboard Table (LIVE!)
```
┌─────┬──────────────────────┬────────┬──────────┬───────────┬──────────┬─────────────┐
│ #   │ USER                 │ RUCKS  │ DISTANCE │ ELEVATION │ CALORIES │ POWERPOINTS │
├─────┼──────────────────────┼────────┼──────────┼───────────┼──────────┼─────────────┤
│ 1🥇 │ [👤] @user1 🟢       │   42   │  312.5km │  2,450m   │  15,230  │ 8,420 ↗️    │
│ 2🥈 │ [👤] @user2 🔴LIVE   │   38   │  298.1km │  2,103m   │  14,892  │ 7,985 ⚡    │
│ 3🥉 │ [👤] @user3          │   35   │  276.8km │  1,987m   │  13,456  │ 7,234 ↘️    │
│ 4   │ [👤] @user4 🟡       │   33   │  245.2km │  1,756m   │  12,108  │ 6,892       │
└─────┴──────────────────────┴────────┴──────────┴───────────┴──────────┴─────────────┘

Live Indicators:
🟢 Online now          🔴 Currently rucking     🟡 Recently active
⚡ Just gained points   ↗️ Rank increased        ↘️ Rank decreased
🥇🥈🥉 Top 3 medals     💥 Milestone achieved    🔥 On a streak
```

## Data Requirements

### User Data Structure
```dart
class LeaderboardUser {
  final String userId;
  final String username;
  final String? profileImageUrl;
  final String? gender; // for default avatar selection
  final LeaderboardStats stats;
  final DateTime lastRuckDate;
  final bool isCurrentUser;
}

class LeaderboardStats {
  final int totalRucks;
  final double totalDistanceKm;
  final double totalElevationM;
  final int totalCalories;
  final int totalPowerPoints;
  final double averageDistance;
  final double averagePace;
}
```

### API Endpoints

#### Get Leaderboard Data
```
GET /api/leaderboard
Query Parameters:
- sortBy: rucks|distance|elevation|calories|powerpoints
- order: asc|desc
- limit: number (default: 100)
- offset: number (default: 0)

Response:
{
  "users": [LeaderboardUser],
  "currentUserRank": number,
  "totalUsers": number,
  "lastUpdated": "ISO8601"
}
```

#### Real-time Updates (LIVE!)
```
WebSocket: /ws/leaderboard (persistent connection)
Events:
- user_ruck_completed: { userId, newStats, newRank, animation: "rank_change" }
- user_ruck_started: { userId, status: "active" } // Show "RUCKING NOW" indicator
- user_ruck_progress: { userId, currentDistance, estimatedFinish } // Live progress
- leaderboard_position_changed: { userId, oldRank, newRank, animation: "smooth_move" }
- user_online_status: { userId, isOnline } // Show who's currently active
- daily_stats_milestone: { userId, milestone: "100_rucks", celebration: true }

Connection Management:
- Auto-reconnect on disconnect
- Heartbeat every 30 seconds
- Fallback polling if WebSocket fails
- Queue events during brief disconnections
```

## UI/UX Design

### Color Scheme
- **Gold**: #FFD700 (1st place)
- **Silver**: #C0C0C0 (2nd place) 
- **Bronze**: #CD7F32 (3rd place)
- **Primary**: App's existing primary color
- **Background**: Dark theme with gradient

### Typography
- **Headers**: Bangers font (existing app style)
- **Stats**: Bold, large numbers
- **Usernames**: Medium weight, readable

### Avatar System
- **Profile Image**: User's uploaded photo (circular, 40px)
- **Male Default**: 👨‍💪 or custom male avatar
- **Female Default**: 👩‍💪 or custom female avatar
- **Unknown**: 👤 generic avatar

### Animations

#### Real-time Update Animation
```dart
// When a user completes a ruck:
1. Highlight the updated row with a pulse effect
2. Animate rank changes with smooth position transitions
3. Show a brief "+X points" floating animation
4. Update stats with a counting animation
```

#### Sort Animation
```dart
// When user changes sort:
1. Fade out current list (200ms)
2. Rearrange data
3. Fade in new order with staggered animation (300ms)
```

#### Pull-to-Refresh
```dart
// Custom refresh animation:
1. Show ruck-themed loading indicator
2. Animate leaderboard rebuild
3. Highlight any rank changes
```

## Features

### Core Features
1. **Sortable Columns**: Tap any column header to sort
2. **User Profiles**: Tap username/avatar to view public profile
3. **Real-time Updates**: Live updates when rucks are completed
4. **Current User Highlight**: Highlight current user's row
5. **Rank Indicators**: Special styling for top 3 positions

### Advanced Features
1. **Search**: Find specific users
2. **Filters**: 
   - Time period (all-time, monthly, weekly)
   - Gender
   - Location/region
3. **Achievements**: Show badges next to usernames
4. **Trends**: Show rank change indicators (↑↓)

### Responsive Design
- **Mobile**: Stack columns for smaller screens
- **Tablet**: Full table layout
- **Landscape**: Optimized column widths

## Technical Implementation

### State Management
```dart
// Bloc pattern
class LeaderboardBloc extends Bloc<LeaderboardEvent, LeaderboardState> {
  // Events: LoadLeaderboard, SortChanged, UserRuckCompleted, RefreshRequested
  // States: Loading, Loaded, Error, Updating
}
```

### Real-Time Strategy
```dart
// NO traditional caching - keep it ALIVE!
// Persistent WebSocket connection for instant updates
// Local state updates immediately on events
// Background sync every 30 seconds for missed events
// Only cache user avatars/profile images (static data)
```

### Performance Optimizations
```dart
// Virtual scrolling for large leaderboards
// Lazy loading of user profile images
// Debounced search input
// Efficient list updates for real-time changes
```

## File Structure
```
lib/features/leaderboard/
├── data/
│   ├── models/
│   │   ├── leaderboard_user.dart
│   │   └── leaderboard_stats.dart
│   ├── repositories/
│   │   └── leaderboard_repository.dart
│   └── datasources/
│       ├── leaderboard_remote_datasource.dart
│       └── leaderboard_local_datasource.dart
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
├── presentation/
│   ├── bloc/
│   │   ├── leaderboard_bloc.dart
│   │   ├── leaderboard_event.dart
│   │   └── leaderboard_state.dart
│   ├── pages/
│   │   └── leaderboard_screen.dart
│   └── widgets/
│       ├── leaderboard_table.dart
│       ├── leaderboard_row.dart
│       ├── sort_header.dart
│       ├── user_avatar.dart
│       └── rank_indicator.dart
└── leaderboard_injection.dart
```

## User Stories

### Primary User Stories
1. **As a user**, I want to see how I rank against other ruckers globally
2. **As a user**, I want to sort the leaderboard by different metrics to see who leads in each category
3. **As a user**, I want to view other users' public profiles to see their ruck history
4. **As a user**, I want to see real-time updates when someone completes a ruck
5. **As a user**, I want to find specific users on the leaderboard

### Secondary User Stories
1. **As a competitive user**, I want to see my rank change immediately after completing a ruck
2. **As a user**, I want to filter the leaderboard by time periods to see recent performance
3. **As a user**, I want to see achievements and badges next to usernames
4. **As a user**, I want smooth animations that make the leaderboard feel alive

## Success Metrics
- **Engagement**: Time spent on leaderboard page
- **Retention**: Users returning to check rankings
- **Social**: Profile views generated from leaderboard
- **Motivation**: Correlation between leaderboard usage and ruck frequency

## Future Enhancements
1. **Team Leaderboards**: Company/group competitions
2. **Challenges**: Monthly/weekly challenges with special rankings
3. **Achievements**: Unlock badges visible on leaderboard
4. **Social Features**: Follow users, comment on achievements
5. **Analytics**: Personal progress tracking vs. community

## Technical Notes
- Ensure privacy: Only show public ruck data
- Handle large datasets efficiently
- Implement proper error handling for network issues
- Consider rate limiting for real-time updates
- Ensure accessibility compliance

# Public Profile Page & Social Following Implementation Plan

## 1. Overview

This document outlines the implementation plan for creating public profile pages and social following functionality. Users will be able to view other users' profiles, follow them, and receive notifications about their activities.

## 2. Core Features

### 2.1 Public Profile Page
- **Access**: Tap on any user's avatar from ruck buddies, duels, clubs, or events pages
- **Content**: User's name, avatar, aggregate stats, clubs, duels record, events history
- **Social**: Follow/unfollow button, followers/following counts and lists

### 2.2 Social Following System
- **Follow/Unfollow**: Users can follow/unfollow other users
- **Notifications**: Followers get notified of new rucks, followers get notified of new followers
- **Discovery**: Filter ruck buddies page by followed users only
- **Social Graph**: View followers/following lists with quick follow/unfollow actions

## 3. Database Schema Changes

### 3.1 User Table Updates

#### Add Privacy Settings to `public.user`
```sql
-- Add privacy column to existing user table
ALTER TABLE public.user 
ADD COLUMN is_profile_private BOOLEAN DEFAULT false;

-- Index for privacy queries
CREATE INDEX idx_user_profile_private ON public.user(is_profile_private);
```

### 3.2 New Tables

#### `public.user_follows`
```sql
CREATE TABLE public.user_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES public.user(id) ON DELETE CASCADE,
    followed_id UUID NOT NULL REFERENCES public.user(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(follower_id, followed_id),
    CHECK (follower_id != followed_id) -- Users can't follow themselves
);

-- Indexes for performance
CREATE INDEX idx_user_follows_follower ON public.user_follows(follower_id);
CREATE INDEX idx_user_follows_followed ON public.user_follows(followed_id);
CREATE INDEX idx_user_follows_created_at ON public.user_follows(created_at);
```

#### `public.user_profile_stats` (Optional - for caching)
```sql
CREATE TABLE public.user_profile_stats (
    user_id UUID PRIMARY KEY REFERENCES public.user(id) ON DELETE CASCADE,
    total_rucks INTEGER DEFAULT 0,
    total_distance_km DECIMAL(10,2) DEFAULT 0,
    total_duration_seconds INTEGER DEFAULT 0,
    total_elevation_gain_m DECIMAL(10,2) DEFAULT 0,
    total_calories_burned DECIMAL(10,2) DEFAULT 0,
    followers_count INTEGER DEFAULT 0,
    following_count INTEGER DEFAULT 0,
    clubs_count INTEGER DEFAULT 0,
    duels_won INTEGER DEFAULT 0,
    duels_lost INTEGER DEFAULT 0,
    events_completed INTEGER DEFAULT 0,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 3.4 RLS Policies

#### user_follows policies
```sql
-- Enable RLS
ALTER TABLE public.user_follows ENABLE ROW LEVEL SECURITY;

-- Users can view follow relationships, but only for public profiles
CREATE POLICY "Users can view follow relationships for public profiles" ON public.user_follows
    FOR SELECT USING (
        -- Can see relationships involving public profiles
        (SELECT is_profile_private FROM public.user WHERE id = followed_id) = false
        OR 
        -- Can see relationships involving yourself
        (auth.uid() = follower_id OR auth.uid() = followed_id)
    );

-- Users can only create follows where they are the follower and target is public
CREATE POLICY "Users can create follows where they are follower and target is public" ON public.user_follows
    FOR INSERT WITH CHECK (
        auth.uid() = follower_id 
        AND (SELECT is_profile_private FROM public.user WHERE id = followed_id) = false
    );

-- Users can only delete follows where they are the follower
CREATE POLICY "Users can delete follows where they are follower" ON public.user_follows
    FOR DELETE USING (auth.uid() = follower_id);
```

#### user_profile_stats policies
```sql
-- Enable RLS
ALTER TABLE public.user_profile_stats ENABLE ROW LEVEL SECURITY;

-- All users can view profile stats
CREATE POLICY "All users can view profile stats" ON public.user_profile_stats
    FOR SELECT USING (true);

-- Only system can insert/update profile stats
CREATE POLICY "System can manage profile stats" ON public.user_profile_stats
    FOR ALL USING (auth.uid() IS NULL); -- Only service role
```

## 4. Backend API Endpoints

### 4.1 Profile Endpoints

#### GET `/users/{userId}/profile`
```typescript
Response: {
  user: {
    id: string,
    username: string,
    avatarUrl: string,
    createdAt: string,
    isFollowing: boolean,
    isFollowedBy: boolean,
    isPrivateProfile: boolean
  },
  stats: {
    totalRucks: number,
    totalDistanceKm: number,
    totalDurationSeconds: number,
    totalElevationGainM: number,
    totalCaloriesBurned: number,
    followersCount: number,
    followingCount: number,
    clubsCount: number,
    duelsWon: number,
    duelsLost: number,
    eventsCompleted: number
  } | null, // null if profile is private
  clubs: Club[] | null, // null if profile is private
  recentRucks: RuckSession[] | null // null if profile is private
}
```

### Implementation Details for GET /users/{userId}/profile
- **Authentication**: Require authenticated user. Use Supabase auth to get current_user_id.
- **Privacy Check**: If target user's is_profile_private=true and current_user_id != userId, return only basic user info with stats/clubs/recentRucks=null.
- **User Fetch**: SELECT id, username, avatar_url, created_at, is_profile_private FROM public.user WHERE id = {userId}.
- **Follow Status**: Check if exists in user_follows for isFollowing (current follows target) and isFollowedBy (target follows current).
- **Stats Aggregation**: If not private or own profile, run SQL: SELECT COUNT(*) as total_rucks, SUM(distance_km) as total_distance_km, etc. FROM ruck_sessions WHERE user_id = {userId}. Use user_profile_stats table if implemented for caching.
- **Clubs Fetch**: If allowed, SELECT * FROM clubs JOIN club_members ON clubs.id = club_members.club_id WHERE club_members.user_id = {userId}.
- **Recent Rucks**: If allowed, SELECT * FROM ruck_sessions WHERE user_id = {userId} ORDER BY end_time DESC LIMIT 5.
- **Error Handling**: 404 if user not found, 403 if private and not owner, 500 on DB errors.
- **Optimization**: Cache response for 1 hour if not own profile.

#### GET `/users/{userId}/followers`
```typescript
Response: {
  followers: {
    id: string,
    username: string,
    avatarUrl: string,
    isFollowing: boolean,
    followedAt: string
  }[],
  pagination: PaginationInfo
}
```

#### GET `/users/{userId}/following`
```typescript
Response: {
  following: {
    id: string,
    username: string,
    avatarUrl: string,
    isFollowing: boolean,
    followedAt: string
  }[],
  pagination: PaginationInfo
}
```

### 4.2 Follow/Unfollow Endpoints

#### POST `/users/{userId}/follow`
```typescript
Request: {} // Empty body
Response: {
  success: boolean,
  isFollowing: boolean,
  followersCount: number,
  error?: string // "Profile is private" if attempting to follow private profile
}
```

#### DELETE `/users/{userId}/follow`
```typescript
Response: {
  success: boolean,
  isFollowing: boolean,
  followersCount: number
}
```

### 4.3 Social Feed Endpoints

#### GET `/social/following-feed`
```typescript
// Returns recent rucks from followed users
Response: {
  rucks: RuckBuddy[],
  pagination: PaginationInfo
}
```

## 5. Frontend Implementation

### 5.1 New Pages

#### `lib/features/profile/presentation/pages/public_profile_screen.dart`
```dart
class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({required this.userId});
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  // Profile data, stats, follow status
  // Tab controller for different sections
}

// UI Layout Note:
// - Profile picture and name should be left-aligned.
// - Followers count and Following count should be right-aligned.
// - Tapping on followers count opens FollowersScreen with list of followers, allowing easy follow-back or unfollow.
// - Tapping on following count opens FollowingScreen with list of followed users, allowing easy unfollow.
```

#### `lib/features/profile/presentation/pages/followers_screen.dart`
```dart
class FollowersScreen extends StatefulWidget {
  final String userId;
  final String title; // "Followers" or "Following"
  final bool isFollowersPage;
}
```

### 5.2 New Widgets

#### `lib/features/profile/presentation/widgets/profile_header.dart`
```dart
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final bool isOwnProfile;
  final VoidCallback? onFollowTap;
  final VoidCallback? onMessageTap;
  // Shows "This profile is private" message when needed
}
```

#### `lib/features/profile/presentation/widgets/profile_stats_grid.dart`
```dart
class ProfileStatsGrid extends StatelessWidget {
  final UserProfileStats stats;
  final VoidCallback? onFollowersPressed;
  final VoidCallback? onFollowingPressed;
}
```

#### `lib/features/profile/presentation/widgets/follow_button.dart`
```dart
class FollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool isLoading;
  final VoidCallback onPressed;
}
```

#### `lib/features/profile/presentation/widgets/social_user_tile.dart`
```dart
// Reusable tile for followers/following lists
class SocialUserTile extends StatelessWidget {
  final SocialUser user;
  final VoidCallback? onFollowPressed;
  final VoidCallback? onTap;
}
```

### 5.3 New Blocs

#### `lib/features/profile/presentation/bloc/public_profile_bloc.dart`
```dart
// Events
abstract class PublicProfileEvent {}
class LoadPublicProfile extends PublicProfileEvent {
  final String userId;
}
class ToggleFollow extends PublicProfileEvent {
  final String userId;
}

// States
abstract class PublicProfileState {}
class PublicProfileInitial extends PublicProfileState {}
class PublicProfileLoading extends PublicProfileState {}
class PublicProfileLoaded extends PublicProfileState {
  final UserProfile profile;
  final UserProfileStats? stats; // null if private profile
  final List<Club>? clubs; // null if private profile
  final List<RuckSession>? recentRucks; // null if private profile
}
class PublicProfileError extends PublicProfileState {
  final String message;
}
```

#### `lib/features/profile/presentation/bloc/social_list_bloc.dart`
```dart
// For followers/following lists
abstract class SocialListEvent {}
class LoadSocialList extends SocialListEvent {
  final String userId;
  final bool isFollowersPage;
}
class ToggleFollowUser extends SocialListEvent {
  final String userId;
}

abstract class SocialListState {}
class SocialListLoaded extends SocialListState {
  final List<SocialUser> users;
  final bool hasMore;
}
```

### 5.4 Domain Models

#### `lib/features/profile/domain/entities/user_profile.dart`
```dart
class UserProfile {
  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isPrivateProfile;
}
```

#### `lib/features/profile/domain/entities/user_profile_stats.dart`
```dart
class UserProfileStats {
  final int totalRucks;
  final double totalDistanceKm;
  final int totalDurationSeconds;
  final double totalElevationGainM;
  final double totalCaloriesBurned;
  final int followersCount;
  final int followingCount;
  final int clubsCount;
  final int duelsWon;
  final int duelsLost;
  final int eventsCompleted;
}
```

#### `lib/features/profile/domain/entities/social_user.dart`
```dart
class SocialUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final bool isFollowing;
  final DateTime followedAt;
}
```

### 5.5 Repository & Service

#### `lib/features/profile/domain/repositories/profile_repository.dart`
```dart
abstract class ProfileRepository {
  Future<UserProfile> getPublicProfile(String userId);
  Future<UserProfileStats> getProfileStats(String userId);
  Future<List<SocialUser>> getFollowers(String userId, {int page = 1});
  Future<List<SocialUser>> getFollowing(String userId, {int page = 1});
  Future<bool> followUser(String userId);
  Future<bool> unfollowUser(String userId);
}
```

#### `lib/features/profile/data/repositories/profile_repository_impl.dart`
```dart
class ProfileRepositoryImpl implements ProfileRepository {
  final ApiClient _apiClient;
  final ProfileService _profileService;
  
  // Implementation using existing services
}
```

#### `lib/features/profile/data/services/profile_service.dart`
```dart
abstract class ProfileService {
  Future<UserProfile> getPublicProfile(String userId);
  Future<UserProfileStats> getProfileStats(String userId);
  Future<List<SocialUser>> getFollowers(String userId, {int page = 1});
  Future<List<SocialUser>> getFollowing(String userId, {int page = 1});
  Future<bool> followUser(String userId);
  Future<bool> unfollowUser(String userId);
}
```

## 6. Existing Services to Reuse

### 6.1 Stats Service
- **File**: `lib/features/dashboard/data/services/stats_service.dart`
- **Reuse**: Aggregate stats calculation logic
- **Modification**: Extend to work with any user ID, not just current user

### 6.2 History Service
- **File**: `lib/features/dashboard/data/services/history_service.dart`
- **Reuse**: Recent rucks, clubs, events data
- **Modification**: Filter by user ID parameter

### 6.3 Notification Service
- **File**: `lib/core/services/firebase_messaging_service.dart`
- **Reuse**: Push notification infrastructure
- **Extension**: Add follow/unfollow notification types

### 6.4 API Client
- **File**: `lib/core/services/api_client.dart`
- **Reuse**: HTTP client for new endpoints
- **No changes needed**

## 7. Profile Privacy Settings

### 7.1 Settings Page Updates

#### Add Privacy Toggle to Profile Settings
```dart
// lib/features/profile/presentation/pages/profile_settings_screen.dart
class ProfileSettingsScreen extends StatelessWidget {
  // Add privacy toggle switch
  // "Make my profile private" - hides all activity data
}
```

#### Privacy Settings Repository
```dart
// lib/features/profile/domain/repositories/profile_settings_repository.dart
abstract class ProfileSettingsRepository {
  Future<bool> updatePrivacySetting(bool isPrivate);
  Future<bool> getPrivacySetting();
}
```

### 7.2 Privacy Behavior

#### When Profile is Private:
- ✅ **Visible**: Username, avatar, join date
- ❌ **Hidden**: Stats, clubs, duels, events, recent rucks, followers/following lists
- ❌ **Blocked**: Following the user (returns error)
- ✅ **Accessible**: Own profile data (user can still see their own data)

#### Privacy API Endpoint
```typescript
// PATCH /users/me/privacy
Request: {
  isPrivateProfile: boolean
}

Response: {
  success: boolean,
  isPrivateProfile: boolean
}
```

## 8. Navigation Updates

### 7.1 Avatar Tap Navigation
Update existing avatar widgets in:
- `lib/features/ruck_buddies/presentation/widgets/ruck_buddy_card.dart`
- `lib/features/duels/presentation/widgets/duel_card.dart`
- `lib/features/clubs/presentation/widgets/club_member_tile.dart`
- `lib/features/events/presentation/widgets/event_participant_tile.dart`

### 7.2 New Routes
```dart
// lib/core/navigation/app_routes.dart
class AppRoutes {
  static const String publicProfile = '/profile/:userId';
  static const String followers = '/profile/:userId/followers';
  static const String following = '/profile/:userId/following';
}
```

## 8. Notification Updates

### 8.1 New Notification Types
```dart
// lib/core/services/firebase_messaging_service.dart
enum NotificationType {
  // ... existing types
  NEW_FOLLOWER,
  FOLLOWER_COMPLETED_RUCK,
}
```

### 8.2 Backend Notification Triggers
```sql
-- Function to send follow notification
CREATE OR REPLACE FUNCTION notify_new_follower()
RETURNS TRIGGER AS $$
BEGIN
  -- Send notification to the followed user
  INSERT INTO public.notifications (
    user_id,
    type,
    title,
    body,
    data
  ) VALUES (
    NEW.followed_id,
    'NEW_FOLLOWER',
    'New Follower',
    (SELECT username FROM public.user WHERE id = NEW.follower_id) || ' started following you',
    json_build_object('followerId', NEW.follower_id)
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for new follows
CREATE TRIGGER trigger_new_follower
  AFTER INSERT ON public.user_follows
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_follower();
```

## 9. Ruck Buddies Page Updates

### 9.1 Filter Addition
```dart
// lib/features/ruck_buddies/presentation/pages/ruck_buddies_screen.dart
enum RuckBuddiesFilter {
  ALL,
  FOLLOWING_ONLY,
  RECENT,
  NEARBY
}
```

### 9.2 Filter Implementation
- Add filter chip/button to ruck buddies page
- Modify ruck buddies query to filter by followed users
- Update BLoC to handle filter state

## 10. Questions & Considerations

### 10.1 Technical Questions
1. ✅ **Profile Privacy**: Users can mark their profile private to hide all activity data
2. ✅ **Follow Limits**: No limits on follow counts for now
3. **Mutual Follows**: Should we show mutual followers/following?
4. **Search**: Should users be able to search for other users to follow?

### 10.2 UX Questions
1. **Profile Access**: Should profiles be accessible without login?
2. **Follow Suggestions**: Should we suggest users to follow based on clubs/location?
3. ✅ **Activity Privacy**: Private profiles hide all activity data except basic info
4. **Blocking**: Should we implement user blocking functionality?

### 10.3 Performance Considerations
1. **Stats Caching**: Should we cache profile stats for performance?
2. **Feed Pagination**: How many items should we show per page?
3. **Real-time Updates**: Should follow counts update in real-time?

## 11. Implementation Timeline

### Phase 1: Backend & Database (Week 1)
- [ ] Create database tables and RLS policies
- [ ] Implement API endpoints
- [ ] Set up notification triggers
- [ ] Add profile stats caching

### Phase 2: Core Frontend (Week 2)
- [ ] Create profile page and widgets
- [ ] Implement follow/unfollow functionality
- [ ] Add navigation from existing pages
- [ ] Create followers/following lists

### Phase 3: Social Features (Week 3)
- [ ] Add ruck buddies filtering
- [ ] Implement notifications
- [ ] Add social user tiles
- [ ] Testing and bug fixes

### Phase 4: Polish & Optimization (Week 4)
- [ ] Performance optimizations
- [ ] UI/UX improvements
- [ ] Error handling
- [ ] Documentation

## 12. Testing Strategy

### 12.1 Unit Tests
- Repository implementations
- BLoC state management
- Service layer logic
- Model conversions

### 12.2 Integration Tests
- API endpoint functionality
- Database operations
- Notification delivery
- Authentication flows

### 12.3 E2E Tests
- Profile viewing flow
- Follow/unfollow actions
- Navigation between pages
- Notification handling

## 13. Security Considerations

### 13.1 Data Privacy
- Ensure RLS policies are properly configured
- Validate user permissions for all operations
- Sanitize user inputs

### 13.2 Rate Limiting
- Implement rate limiting for follow/unfollow actions
- Prevent spam following
- Monitor for abuse patterns

### 13.3 Authentication
- Ensure all endpoints require proper authentication
- Validate user ownership for sensitive operations
- Implement proper error handling

---

This plan provides a comprehensive roadmap for implementing the public profile page and social following features while maintaining consistency with existing patterns and best practices.

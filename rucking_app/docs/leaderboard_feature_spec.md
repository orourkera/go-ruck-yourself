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
│ 1🥇 │ [👤] @user1          │   42   │  312.5km │  2,450m   │  15,230  │ 8,420 ↗️    │
│     │     Austin, TX       │        │          │           │          │             │
│ 2🥈 │ [👤] @user2 🟢LIVE   │   38   │  298.1km │  2,103m   │  14,892  │ 7,985 ⚡    │
│     │     Denver, CO       │        │          │           │          │             │
│ 3🥉 │ [👤] @user3          │   35   │  276.8km │  1,987m   │  13,456  │ 7,234 ↘️    │
│     │     Seattle, WA      │        │          │           │          │             │
│ 4   │ [👤] @user4          │   33   │  245.2km │  1,756m   │  12,108  │ 6,892       │
│     │     Miami, FL        │        │          │           │          │             │
└─────┴──────────────────────┴────────┴──────────┴───────────┴──────────┴─────────────┘

Live Indicators:
🟢 Currently rucking    ⚡ Just gained points   ↗️ Rank increased        
↘️ Rank decreased      🥇🥈🥉 Top 3 medals     🔥 On a streak          
💪 Personal best       ❓ Tap POWERPOINTS header for explanation
```

## Data Requirements

### User Data Structure
```dart
class LeaderboardUser {
  final String userId;
  final String username;
  final String? avatarUrl; // matches existing User model
  final String? gender; // for default avatar selection
  final LeaderboardStats stats;
  final DateTime lastRuckDate;
  final String? lastRuckLocation; // "City, State" from reverse geocoding
  final bool isCurrentUser;
}

class LeaderboardStats {
  final int totalRucks;
  final double distanceKm; // matches ruck_session.dart
  final double elevationGainMeters; // matches ruck_session.dart
  final double caloriesBurned; // matches ruck_session.dart
  final double powerPoints; // matches ruck_session.dart (double, not int)
  final double averageDistanceKm;
  final double averagePaceMinKm; // matches ruck_session.dart
}
```

### API Endpoints

#### Get Leaderboard Data
```
GET /api/leaderboard

🔒 PRIVACY REQUIREMENTS:
- Users with public.Allow_Ruck_Sharing = false MUST be excluded from ALL leaderboard results
- Only users who have explicitly allowed public ruck sharing should appear
- Backend MUST filter users at query level, not in application code

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
- user_activity_status: { userId, isActive } // Show who's currently rucking
- personal_best_achieved: { userId, metric: "distance", newRecord: true } // Optional celebration

Connection Management:
- Auto-reconnect on disconnect
- Heartbeat every 30 seconds
- Fallback polling if WebSocket fails
- Queue events during brief disconnections
```

## UI/UX Design

### Power Points Explanation Modal
```
┌─────────────────────────────────────────┐
│  💪 POWER POINTS EXPLAINED              │
├─────────────────────────────────────────┤
│                                         │
│  Power Points measure the total effort  │
│  and challenge of your rucks.           │
│                                         │
│  📊 CALCULATION:                        │
│  Power Points = Weight × Distance ×     │
│                 Elevation Gain          │
│                                         │
│  🎒 Weight: Your ruck weight (kg)       │
│  📏 Distance: Total distance (km)       │
│  ⛰️  Elevation: Total climb (meters)     │
│                                         │
│  💡 EXAMPLE:                            │
│  20kg ruck × 5km × 100m elevation      │
│  = 10,000 Power Points                 │
│                                         │
│  🏆 Higher weight, longer distance,     │
│     and more elevation = more points!   │
│                                         │
│           [GOT IT] [LEARN MORE]         │
└─────────────────────────────────────────┘
```

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
6. **Power Points Explanation**: Tap POWERPOINTS header to show calculation modal

### Advanced Features
1. **Search**: Find specific users
2. **Filters**: 
   - Time period (all-time, monthly, weekly)
   - Gender
   - Location/region
3. **Trends**: Show rank change indicators (↑↓)

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

### Performance Optimizations (World-Class)

#### Frontend Optimizations
```dart
// 🚀 Virtual Scrolling with flutter_list_view
// Only render visible items + small buffer
// Handle 10,000+ users without performance loss

// ⚡ Efficient List Updates
// Use AnimatedList for smooth insertions/deletions
// Batch updates to prevent excessive rebuilds
// Smart diffing algorithm for minimal redraws

// 🖼️ Image Optimization
// Lazy load avatars with cached_network_image
// Progressive loading with placeholders
// Memory-efficient image caching

// 🔍 Search Optimization
// Debounced input (300ms)
// Client-side filtering for <1000 users
// Server-side search for larger datasets

// 📱 Memory Management
// Dispose unused widgets aggressively
// Use const constructors everywhere
// Optimize rebuild scope with RepaintBoundary
```

#### Backend Performance (Redis + WebSocket)
```python
# 🔥 Redis-Powered Leaderboard
# Use Redis Sorted Sets (ZADD, ZRANGE) - O(log N) operations
# Pre-computed rankings updated on ruck completion
# Sub-millisecond leaderboard queries

# Example Redis Structure:
REDIS_KEYS = {
    'leaderboard:powerpoints': 'sorted_set',  # ZADD user_id score
    'leaderboard:distance': 'sorted_set',
    'leaderboard:rucks': 'sorted_set',
    'user:stats:{user_id}': 'hash',  # HSET for user details
    'online_users': 'set',  # SADD for online tracking
    'active_ruckers': 'set'  # Currently rucking users
}

# ⚡ WebSocket Optimization
# Use Socket.IO with Redis adapter for horizontal scaling
# Room-based updates (only send to leaderboard viewers)
# Compression for large payloads
# Connection pooling and auto-reconnection

# 🎯 Smart Update Strategy
# Only broadcast rank changes that affect visible users
# Batch multiple updates into single WebSocket message
# Use delta updates instead of full leaderboard refreshes
```

#### Database Optimization
```sql
-- 📊 Real-Time Leaderboard Query (No New Tables!)
-- Uses existing ruck_sessions and users tables
SELECT 
    u.user_id,
    u.username,
    u.avatar_url,
    COUNT(rs.ruck_id) as total_rucks,
    COALESCE(SUM(rs.distance_km), 0) as total_distance_km,
    COALESCE(SUM(rs.elevation_gain_meters), 0) as total_elevation_gain_meters,
    COALESCE(SUM(rs.calories_burned), 0) as total_calories_burned,
    COALESCE(SUM(rs.power_points), 0) as total_power_points,
    COALESCE(AVG(rs.distance_km), 0) as average_distance_km,
    COALESCE(AVG(rs.average_pace_min_km), 0) as average_pace_min_km,
    MAX(rs.completed_at) as last_ruck_date,
    -- Get location from most recent ruck
    (SELECT location_name FROM ruck_sessions rs2 
     WHERE rs2.user_id = u.user_id AND rs2.is_public = true 
     AND rs2.status = 'completed' AND rs2.location_name IS NOT NULL
     ORDER BY rs2.completed_at DESC LIMIT 1) as last_ruck_location
FROM users u
LEFT JOIN ruck_sessions rs ON u.user_id = rs.user_id 
    AND rs.is_public = true AND rs.status = 'completed'
WHERE u.public_allow_ruck_sharing = true  -- 🔒 PRIVACY: Only users who allow sharing
GROUP BY u.user_id, u.username, u.avatar_url
HAVING COUNT(rs.ruck_id) > 0  -- Only users with public rucks
ORDER BY total_power_points DESC
LIMIT 100;

-- 🚀 Existing Indexes (Already Optimized)
-- These indexes should already exist on your ruck_sessions table:
-- idx_ruck_sessions_user_id
-- idx_ruck_sessions_status
-- idx_ruck_sessions_is_public
-- idx_ruck_sessions_completed_at

-- ⚡ Additional Composite Index for Performance
CREATE INDEX CONCURRENTLY idx_ruck_sessions_leaderboard 
ON ruck_sessions (user_id, is_public, status, completed_at DESC)
WHERE is_public = true AND status = 'completed';
```

#### Real-Time Architecture
```python
# 🏗️ Microservices Architecture
services = {
    'leaderboard-service': 'FastAPI + Redis + WebSocket',
    'ruck-completion-service': 'Event-driven updates',
    'user-presence-service': 'Online/offline tracking',
    'notification-service': 'Real-time alerts'
}

# 📡 Event-Driven Updates
class LeaderboardEventHandler:
    async def on_ruck_completed(self, event):
        # 1. Update Redis sorted sets (1-2ms)
        await redis.zadd('leaderboard:powerpoints', event.user_id, new_score)
        
        # 2. Calculate rank changes (2-3ms)
        old_rank = await redis.zrevrank('leaderboard:powerpoints', event.user_id)
        new_rank = await redis.zrevrank('leaderboard:powerpoints', event.user_id)
        
        # 3. Broadcast only to affected users (5ms)
        if rank_changed:
            await websocket.emit_to_room('leaderboard', {
                'type': 'rank_change',
                'user_id': event.user_id,
                'old_rank': old_rank,
                'new_rank': new_rank,
                'animation': 'smooth_move'
            })

# 🔄 Connection Management
class WebSocketManager:
    def __init__(self):
        self.connections = {}  # user_id -> connection
        self.rooms = defaultdict(set)  # room -> set of user_ids
        
    async def join_leaderboard(self, user_id, connection):
        self.rooms['leaderboard'].add(user_id)
        self.connections[user_id] = connection
        
        # Send initial leaderboard data
        leaderboard_data = await self.get_leaderboard_chunk(0, 100)
        await connection.send(leaderboard_data)
```

#### Caching Strategy (Multi-Layer)
```python
# 🏎️ 3-Tier Caching Strategy
caching_layers = {
    'L1_Browser': 'Client-side caching (5 minutes)',
    'L2_CDN': 'CloudFlare edge caching (1 minute)', 
    'L3_Redis': 'Redis in-memory (real-time)',
    'L4_Database': 'PostgreSQL with materialized views'
}

# ⚡ Cache Invalidation Strategy
class CacheManager:
    async def on_ruck_completed(self, user_id):
        # Invalidate only affected cache keys
        await redis.delete(f'user:rank:{user_id}')
        await redis.delete('leaderboard:top100')
        
        # Smart cache warming
        asyncio.create_task(self.warm_leaderboard_cache())
        
    async def warm_leaderboard_cache(self):
        # Pre-compute top 100, 500, 1000 rankings
        for limit in [100, 500, 1000]:
            await redis.setex(
                f'leaderboard:top{limit}',
                300,  # 5 minutes
                await self.compute_leaderboard(limit)
            )
```

#### Location Data Processing
```dart
// 🗺️ Location Processing for Leaderboard
class LocationProcessor {
  static Future<String?> getLocationFromRuck(RuckSession ruck) async {
    if (ruck.waypoints == null || ruck.waypoints!.isEmpty) return null;
    
    // Use the first waypoint (start location) for consistency
    final startPoint = ruck.waypoints!.first;
    final latLng = LatLng(startPoint.latitude, startPoint.longitude);
    
    try {
      // Use existing LocationUtils for reverse geocoding
      final locationName = await LocationUtils.getLocationNameFromLatLng(latLng);
      
      // Format to "City, State" for leaderboard display
      return _formatForLeaderboard(locationName);
    } catch (e) {
      print('Error getting location for leaderboard: $e');
      return null;
    }
  }
  
  static String? _formatForLeaderboard(String locationName) {
    // Extract city and state from formatted location
    // Input: "Central Park • New York • NY"
    // Output: "New York, NY"
    
    final parts = locationName.split(' • ');
    if (parts.length >= 2) {
      // Take last two parts (city, state)
      final city = parts[parts.length - 2];
      final state = parts[parts.length - 1];
      return '$city, $state';
    }
    
    // Fallback to original if can't parse
    return locationName != 'Unknown Location' ? locationName : null;
  }
}
```

#### Power Points Modal Widget
```dart
// 💪 Power Points Explanation Modal
class PowerPointsModal extends StatelessWidget {
  const PowerPointsModal({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Text('💪', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  'POWER POINTS EXPLAINED',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Description
            Text(
              'Power Points measure the total effort and challenge of your rucks.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Formula
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('📊 CALCULATION:', 
                       style: Theme.of(context).textTheme.titleMedium?.copyWith(
                         fontWeight: FontWeight.bold,
                       )),
                  const SizedBox(height: 8),
                  const Text(
                    'Power Points = Weight × Distance × Elevation Gain',
                    style: TextStyle(fontSize: 16, fontFamily: 'monospace'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Components
            _buildComponent('🎒', 'Weight', 'Your ruck weight (kg)'),
            _buildComponent('📏', 'Distance', 'Total distance (km)'),
            _buildComponent('⛰️', 'Elevation', 'Total climb (meters)'),
            const SizedBox(height: 16),
            
            // Example
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text('💡 EXAMPLE:', 
                       style: Theme.of(context).textTheme.titleSmall?.copyWith(
                         fontWeight: FontWeight.bold,
                       )),
                  const SizedBox(height: 4),
                  const Text('20kg ruck × 5km × 100m elevation'),
                  const Text('= 10,000 Power Points', 
                           style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Tip
            Text(
              '🏆 Higher weight, longer distance, and more elevation = more points!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('GOT IT'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to more detailed explanation or help
                    Navigator.of(context).pop();
                    // TODO: Navigate to help/FAQ page
                  },
                  child: const Text('LEARN MORE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildComponent(String emoji, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text('$title:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }
  
  // Static method to show the modal
  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PowerPointsModal(),
    );
  }
}
```

#### Mobile Optimization
```dart
// 📱 Flutter Performance Best Practices
class LeaderboardOptimizations {
  // Use RepaintBoundary for expensive widgets
  Widget buildUserRow(User user) {
    return RepaintBoundary(
      child: UserRowWidget(user: user),
    );
  }
  
  // Implement smart pagination
  void loadMoreUsers() {
    if (_isLoading || !_hasMore) return;
    
    _pagingController.appendPage(
      await _leaderboardService.getUsers(
        offset: _currentOffset,
        limit: 50  // Optimal batch size
      ),
      _currentOffset + 50
    );
  }
  
  // Use efficient list updates
  void updateUserRank(String userId, int newRank) {
    final index = _users.indexWhere((u) => u.id == userId);
    if (index != -1) {
      // Animate to new position
      _animatedListKey.currentState?.insertItem(newRank);
      _animatedListKey.currentState?.removeItem(index, (context, animation) {
        return SlideTransition(
          position: animation.drive(Tween(begin: Offset(1, 0), end: Offset.zero)),
          child: UserRowWidget(user: _users[index]),
        );
      });
    }
  }
}
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
3. **As a user**, I want to see rank trends and movement indicators
4. **As a user**, I want smooth animations that make the leaderboard feel alive

## Success Metrics
- **Engagement**: Time spent on leaderboard page
- **Retention**: Users returning to check rankings
- **Social**: Profile views generated from leaderboard
- **Motivation**: Correlation between leaderboard usage and ruck frequency

## Future Enhancements (Performance-Focused)
1. **Machine Learning Predictions**: Predict rank changes, suggest goals
2. **Edge Computing**: Deploy leaderboard cache to edge locations
3. **GraphQL Subscriptions**: More efficient real-time data fetching
4. **WebAssembly**: Client-side ranking calculations for ultra-fast sorting
5. **Blockchain Integration**: Immutable leaderboard records
6. **AI-Powered Insights**: Personalized performance analytics
7. **Global CDN**: Sub-100ms response times worldwide
8. **Predictive Caching**: Pre-load data based on user behavior patterns

## Performance Benchmarks

### Target Performance Metrics
```
📊 Leaderboard Load Time: <500ms (cold start)
⚡ Real-time Update Latency: <100ms (WebSocket)
🔄 Rank Change Animation: 60fps smooth
📱 Memory Usage: <50MB for 10,000 users
🌐 Network Efficiency: <1KB per update
🔋 Battery Impact: Minimal (optimized WebSocket)
```

### Scalability Targets
```
👥 Concurrent Users: 10,000+ viewing leaderboard
📈 Database Load: <10ms query time for top 1000
🚀 Redis Performance: <1ms for rank lookups
📡 WebSocket Throughput: 1000+ updates/second
💾 Storage Efficiency: Compressed JSON payloads
```

## Technical Notes
- **Privacy**: Only show public ruck data with user consent
- **Scalability**: Horizontal scaling with Redis Cluster + Load Balancers
- **Error Handling**: Circuit breakers, retry logic, graceful degradation
- **Rate Limiting**: Smart throttling to prevent spam/abuse
- **Accessibility**: Screen reader support, high contrast mode
- **Security**: Input validation, SQL injection prevention, DDoS protection
- **Monitoring**: Real-time performance metrics with Grafana/DataDog
- **A/B Testing**: Feature flags for gradual rollout

# RuckingApp API Endpoints Reference

> **IMPORTANT URL CONSTRUCTION NOTE**:
> The base URL is configured as `https://getrucky.com/api` (without a trailing slash).
> When making API requests, **always include a leading slash** in your endpoint paths.
> Example: Use `/rucks/{id}/heart_rate` instead of `rucks/{id}/heart_rate`
> This ensures the URL is properly constructed as `https://getrucky.com/api/rucks/{id}/heart_rate`
> rather than the incorrect `https://getrucky.com/apirucks/{id}/heart_rate`

This document provides a comprehensive list of all API endpoints used in the RuckingApp, organized by feature area.

## Session Management

### Ruck Sessions

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/rucks` | GET | Get list of ruck sessions (supports limit parameter) |
| `/rucks` | POST | Create a new ruck session |
| `/rucks/{id}` | GET | Get details of a specific session |
| `/rucks/{id}` | DELETE | Delete a specific session |
| `/api/rucks/start` | POST | Start a ruck session (send ruck_id in the request body, not in URL) |
| `/rucks/{id}/pause` | POST | Pause a ruck session |
| `/rucks/{id}/resume` | POST | Resume a paused ruck session |
| `/rucks/{id}/complete` | POST | Complete a ruck session |
| `/rucks/{id}/location` | POST | Add location point to a session |
| `/api/rucks/{id}/heartrate` | POST | Add heart rate samples to a session (NOTE: Uses 'heartrate' without underscore!) |

### Photos

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/ruck-photos` | GET | Get photos for a session (with ruck_id parameter) |
| `/ruck-photos` | POST | Upload photos for a session |
| `/ruck-photos?photo_id={id}` | DELETE | Delete a specific photo |

## Statistics

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/stats/monthly` | GET | Get monthly statistics |
| `/stats/yearly` | GET | Get yearly statistics |
| `/stats/weekly` | GET | Get weekly statistics |

## Social Features

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/ruck-likes/check?ruck_id={id}` | GET | Check if user has liked a specific ruck |
| `/rucks/{id}/like` | POST | Like a ruck session |
| `/rucks/{id}/unlike` | POST | Unlike a ruck session |
| `/rucks/{id}/comments` | GET | Get comments for a ruck session |
| `/rucks/{id}/comments` | POST | Add a comment to a ruck session |
| `/rucks/{id}/comments/{comment_id}` | DELETE | Delete a specific comment |

## Community

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/rucks/community` | GET | Get community ruck sessions |
| `/ruck-buddies` | GET | Get ruck buddies |

## User Management

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/api/me` | GET | Get current user profile |
| `/users/profile` | GET | Get current user profile (alternative endpoint) |
| `/users/profile` | PUT | Update current user profile |
| `/users/{id}` | DELETE | Delete a user account |
| `/users/register` | POST | Register a new user account |
| `/auth/login` | POST | Authenticate and login user |
| `/auth/refresh` | POST | Refresh authentication token |
| `/auth/forgot-password` | POST | Request password reset link |

## Notifications

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/notifications/` | GET | Get user notifications |
| `/notifications/{id}/read` | POST | Mark notification as read |
| `/notifications/read-all` | POST | Mark all notifications as read |

> **NOTE**: The notifications table in the database uses `recipient_id` (not `user_id`) to store the user ID.

## Achievements System

| Endpoint | HTTP Method | Description |
|----------|------------|-------------|
| `/achievements` | GET | Get all available achievements |
| `/achievements/categories` | GET | Get achievement categories |
| `/users/{user_id}/achievements` | GET | Get user's earned achievements |
| `/users/{user_id}/achievements/progress` | GET | Get progress toward unearned achievements |
| `/achievements/check/{session_id}` | POST | Check and award achievements for a session |
| `/achievements/stats/{user_id}` | GET | Get achievement statistics for user |
| `/achievements/recent` | GET | Get recently earned achievements across platform |

## Duels

### Duels

- **GET** `/api/duels` - List duels (with filtering by status, type, location)
- **POST** `/api/duels` - Create a new duel challenge
- **GET** `/api/duels/{duel_id}` - Get duel details and participants
- **PUT** `/api/duels/{duel_id}` - Update duel (creator only, limited fields)
- **POST** `/api/duels/{duel_id}/join` - Join a public duel
- **PUT** `/api/duels/{duel_id}/participants/{participant_id}/status` - Update participant status (accept/decline invitation)

### Duel Participants

- **POST** `/api/duels/{duel_id}/participants/{participant_id}/progress` - Update participant progress from completed session
- **GET** `/api/duels/{duel_id}/participants/{participant_id}/progress` - Get participant's detailed progress and contributing sessions
- **GET** `/api/duels/{duel_id}/leaderboard` - Get real-time duel leaderboard and recent activity

### Duel Statistics

- **GET** `/api/duel-stats` - Get current user's duel statistics and recent history
- **GET** `/api/duel-stats/{user_id}` - Get specific user's duel statistics
- **GET** `/api/duel-stats/leaderboard` - Get global duel leaderboards (by wins, completion rate, total duels)
- **GET** `/api/duel-stats/analytics` - Get user's duel analytics and insights over time

### Duel Invitations

- **GET** `/api/duel-invitations` - Get user's received duel invitations
- **PUT** `/api/duel-invitations/{invitation_id}` - Respond to duel invitation (accept/decline)
- **DELETE** `/api/duel-invitations/{invitation_id}` - Cancel sent invitation (inviter only)
- **GET** `/api/duel-invitations/sent` - Get invitations sent by current user

---

## Request/Response Formats

### Session Creation

**Request:**
```json
{
  "ruck_weight_kg": 10.0,
  "notes": "Optional notes",
  "planned_duration_minutes": 60
}
```

### Location Update

**Request:**
```json
{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "elevation": 10.0,
  "timestamp": "2023-01-01T12:00:00Z"
}
```

### Session Completion

**Request:**
```json
{
  "distance_km": 5.0,
  "duration_seconds": 3600,
  "calories_burned": 500,
  "elevation_gain_m": 100,
  "elevation_loss_m": 100,
  "average_pace": 720,
  "ruck_weight_kg": 10.0,
  "notes": "Optional notes",
  "rating": 5,
  "tags": ["morning", "training"],
  "perceived_exertion": 7,
  "weight_kg": 75.0,
  "planned_duration_minutes": 60,
  "paused_duration_seconds": 300
}
```

### Heart Rate Samples

**Request:**
```json
{
  "samples": [
    {
      "timestamp": "2023-01-01T12:01:00Z",
      "bpm": 120
    },
    {
      "timestamp": "2023-01-01T12:02:00Z",
      "bpm": 125
    }
  ]
}
```

## Notes

- All date/time values use ISO 8601 format
- Authentication is handled via Bearer tokens in the Authorization header
- Most successful responses return a status code of 200 or 201
- Error responses typically include a `message` field with details
- Endpoints may change in future API versions

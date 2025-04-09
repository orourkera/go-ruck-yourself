Rucking App API Documentation
Base URL
https://api.ruckingapp.com/v1
Authentication
Most endpoints require authentication via JWT token.

Headers:

Authorization: Bearer {jwt_token}
User Management
Register User
POST /users/register
Request Body:

{
  "email": "user@example.com",
  "password": "securepassword",
  "name": "John Doe",
  "weight_kg": 75.5,
  "height_cm": 180,
  "date_of_birth": "1990-01-01"
}
Response (201 Created):

{
  "user_id": "u123456",
  "email": "user@example.com",
  "name": "John Doe",
  "created_at": "2025-04-09T12:00:00Z"
}
Login
POST /auth/login
Request Body:

{
  "email": "user@example.com",
  "password": "securepassword"
}
Response (200 OK):

{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "user_id": "u123456",
    "email": "user@example.com",
    "name": "John Doe"
  }
}
Get User Profile
GET /users/profile
Response (200 OK):

{
  "user_id": "u123456",
  "email": "user@example.com",
  "name": "John Doe",
  "weight_kg": 75.5,
  "height_cm": 180,
  "date_of_birth": "1990-01-01",
  "created_at": "2025-04-09T12:00:00Z",
  "stats": {
    "total_rucks": 42,
    "total_distance_km": 256.8,
    "total_calories": 12450,
    "this_month": {
      "rucks": 5,
      "distance_km": 32.4,
      "calories": 1540
    }
  }
}
Update User Profile
PUT /users/profile
Request Body:

{
  "weight_kg": 74.2,
  "height_cm": 180,
  "name": "John Doe"
}
Response (200 OK):

{
  "user_id": "u123456",
  "email": "user@example.com",
  "name": "John Doe",
  "weight_kg": 74.2,
  "height_cm": 180,
  "updated_at": "2025-04-09T14:30:00Z"
}
Ruck Sessions
Create New Ruck Session
POST /rucks
Request Body:

{
  "ruck_weight_kg": 10.5,
  "user_weight_kg": 75.0,
  "planned_duration_minutes": 60,
  "notes": "Morning ruck around the neighborhood"
}
Response (201 Created):

{
  "ruck_id": "r789012",
  "status": "created",
  "created_at": "2025-04-09T06:30:00Z",
  "ruck_weight_kg": 10.5,
  "user_weight_kg": 75.0,
  "planned_duration_minutes": 60,
  "notes": "Morning ruck around the neighborhood"
}
Start Ruck Session
POST /rucks/{ruck_id}/start
Response (200 OK):

{
  "ruck_id": "r789012",
  "status": "in_progress",
  "started_at": "2025-04-09T06:35:12Z"
}
Record Location Update
POST /rucks/{ruck_id}/location
Request Body:

{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "elevation_meters": 12.5,
  "timestamp": "2025-04-09T06:40:15Z",
  "accuracy_meters": 5.0
}
Response (200 OK):

{
  "recorded": true,
  "current_stats": {
    "distance_km": 1.2,
    "elevation_gain_meters": 24.5,
    "elevation_loss_meters": 12.0,
    "calories_burned": 145,
    "duration_seconds": 303,
    "average_pace_min_km": 12.5
  }
}
Pause Ruck Session
POST /rucks/{ruck_id}/pause
Response (200 OK):

{
  "ruck_id": "r789012",
  "status": "paused",
  "paused_at": "2025-04-09T07:15:22Z",
  "current_stats": {
    "distance_km": 2.5,
    "elevation_gain_meters": 45.0,
    "elevation_loss_meters": 22.5,
    "calories_burned": 320,
    "duration_seconds": 2410,
    "average_pace_min_km": 12.8
  }
}
Resume Ruck Session
POST /rucks/{ruck_id}/resume
Response (200 OK):

{
  "ruck_id": "r789012",
  "status": "in_progress",
  "resumed_at": "2025-04-09T07:20:45Z"
}
Complete Ruck Session
POST /rucks/{ruck_id}/complete
Request Body:

{
  "rating": 4,
  "perceived_exertion": 7,
  "notes": "Good session, hills were challenging",
  "tags": ["morning", "hilly"]
}
Response (200 OK):

{
  "ruck_id": "r789012",
  "status": "completed",
  "completed_at": "2025-04-09T07:45:30Z",
  "final_stats": {
    "distance_km": 5.2,
    "elevation_gain_meters": 110.5,
    "elevation_loss_meters": 110.5,
    "calories_burned": 650,
    "duration_seconds": 4218,
    "average_pace_min_km": 13.5,
    "route_map_url": "https://api.ruckingapp.com/v1/rucks/r789012/map"
  },
  "rating": 4,
  "perceived_exertion": 7,
  "notes": "Good session, hills were challenging",
  "tags": ["morning", "hilly"]
}
Get Ruck Session Details
GET /rucks/{ruck_id}
Response (200 OK):

{
  "ruck_id": "r789012",
  "user_id": "u123456",
  "status": "completed",
  "created_at": "2025-04-09T06:30:00Z",
  "started_at": "2025-04-09T06:35:12Z",
  "completed_at": "2025-04-09T07:45:30Z",
  "ruck_weight_kg": 10.5,
  "user_weight_kg": 75.0,
  "stats": {
    "distance_km": 5.2,
    "elevation_gain_meters": 110.5,
    "elevation_loss_meters": 110.5,
    "calories_burned": 650,
    "duration_seconds": 4218,
    "average_pace_min_km": 13.5
  },
  "rating": 4,
  "perceived_exertion": 7,
  "notes": "Good session, hills were challenging",
  "tags": ["morning", "hilly"]
}
Get Ruck Route Map
GET /rucks/{ruck_id}/map
Response (200 OK):

{
  "ruck_id": "r789012",
  "polyline": "o~peFzrbjVjFrBl@lDoCdP}Ex@gF_D...",
  "start_point": {
    "latitude": 37.7749,
    "longitude": -122.4194
  },
  "end_point": {
    "latitude": 37.7680,
    "longitude": -122.4075
  },
  "waypoints": [
    {
      "latitude": 37.7749,
      "longitude": -122.4194,
      "elevation": 12.5,
      "timestamp": "2025-04-09T06:35:12Z"
    },
    // Additional waypoints...
    {
      "latitude": 37.7680,
      "longitude": -122.4075,
      "elevation": 10.2,
      "timestamp": "2025-04-09T07:45:30Z"
    }
  ]
}
Historical Data
List Recent Ruck Sessions
GET /rucks
Query Parameters:

limit: Number of sessions to return (default: 10, max: 50)
offset: Pagination offset (default: 0)
status: Filter by status (all, created, in_progress, paused, completed)
start_date: Filter by start date (format: YYYY-MM-DD)
end_date: Filter by end date (format: YYYY-MM-DD)
Response (200 OK):

{
  "total": 42,
  "limit": 10,
  "offset": 0,
  "rucks": [
    {
      "ruck_id": "r789012",
      "status": "completed",
      "date": "2025-04-09",
      "distance_km": 5.2,
      "duration_seconds": 4218,
      "calories_burned": 650,
      "ruck_weight_kg": 10.5
    },
    // Additional ruck sessions...
  ]
}
Get Weekly Summary
GET /stats/weekly
Query Parameters:

date: Week containing this date (format: YYYY-MM-DD, default: current date)
Response (200 OK):

{
  "week_start": "2025-04-07",
  "week_end": "2025-04-13",
  "total_rucks": 3,
  "total_distance_km": 13.5,
  "total_duration_seconds": 11520,
  "total_calories_burned": 1680,
  "average_pace_min_km": 14.2,
  "total_elevation_gain_meters": 280.5,
  "daily_breakdown": [
    {
      "date": "2025-04-07",
      "rucks": 1,
      "distance_km": 4.2,
      "calories_burned": 520
    },
    // Other days of the week...
  ]
}
Get Monthly Summary
GET /stats/monthly
Query Parameters:

year: Year (default: current year)
month: Month (1-12, default: current month)
Response (200 OK):

{
  "year": 2025,
  "month": 4,
  "total_rucks": 12,
  "total_distance_km": 62.5,
  "total_duration_seconds": 53280,
  "total_calories_burned": 7850,
  "average_pace_min_km": 14.2,
  "best_ruck": {
    "ruck_id": "r789012",
    "date": "2025-04-09",
    "distance_km": 5.2,
    "calories_burned": 650
  },
  "weekly_breakdown": [
    {
      "week_start": "2025-04-01",
      "week_end": "2025-04-06",
      "rucks": 3,
      "distance_km": 15.2,
      "calories_burned": 1920
    },
    // Other weeks...
  ]
}
Get Yearly Summary
GET /stats/yearly
Query Parameters:

year: Year (default: current year)
Response (200 OK):

{
  "year": 2025,
  "total_rucks": 145,
  "total_distance_km": 780.5,
  "total_duration_seconds": 665280,
  "total_calories_burned": 98500,
  "average_ruck_weight_kg": 12.3,
  "monthly_breakdown": [
    {
      "month": 1,
      "rucks": 12,
      "distance_km": 65.3,
      "calories_burned": 8250
    },
    // Other months...
  ]
}
Calculations
Calculate Estimated Calories
POST /calculations/calories
Request Body:

{
  "user_weight_kg": 75.0,
  "ruck_weight_kg": 10.5,
  "distance_km": 5.0,
  "elevation_gain_meters": 100,
  "duration_minutes": 70
}
Response (200 OK):

{
  "estimated_calories": 625,
  "factors": {
    "base_calories": 375,
    "weight_factor": 1.14,
    "elevation_factor": 1.25,
    "pace_factor": 1.05
  }
}
Error Responses
400 Bad Request
{
  "error": "bad_request",
  "message": "Invalid request parameters",
  "details": {
    "weight_kg": "Must be a positive number"
  }
}
401 Unauthorized
{
  "error": "unauthorized",
  "message": "Authentication required"
}
403 Forbidden
{
  "error": "forbidden",
  "message": "You don't have permission to access this resource"
}
404 Not Found
{
  "error": "not_found",
  "message": "Ruck session not found"
}
500 Server Error
{
  "error": "server_error",
  "message": "An unexpected error occurred",
  "request_id": "req-123456"
}
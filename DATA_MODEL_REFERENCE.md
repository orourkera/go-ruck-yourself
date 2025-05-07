# Ruck Session Data Model Reference

This document maps the data model for a rucking session across all layers:
**Frontend (Flutter/Dart) → API (Python) → Database (SQL)**

---

## Table of Contents
- [Session Properties](#session-properties)
- [Mapping Table](#mapping-table)
- [Example JSON Payload](#example-json-payload)
- [Example SQL Table](#example-sql-table)
- [Notes](#notes)

---

## Session Properties

| Concept                | Dart/Flutter Property        | API Field (Python)         | Database Column (SQL)         |
|------------------------|-----------------------------|----------------------------|-------------------------------|
| Session ID             | `id`                        | `id`                       | `id` (PK, integer)            |
| User ID                | `userId`                    | `user_id`                  | `user_id` (FK, uuid)          |
| Start Time             | `startTime`                 | `start_time`               | `start_time` (timestamp)      |
| End Time               | `endTime`                   | `end_time`                 | `end_time` (timestamp)        |
| Duration (s)           | `durationSeconds`           | `duration_seconds`         | `duration_seconds` (int)      |
| Paused Duration (s)    | `pausedDurationSeconds`     | `paused_duration_seconds`  | `paused_duration_seconds` (int)|
| Planned Duration (min) | `plannedDurationMinutes`    | `planned_duration_minutes` | `planned_duration_minutes` (int)|
| Started At             | `startedAt`                 | `started_at`               | `started_at` (timestamptz)    |
| Ended At               | `endedAt`                   | `ended_at`                 | `ended_at` (timestamptz)      |
| Completed At           | `completedAt`               | `completed_at`             | `completed_at` (timestamptz)  |
| Status                 | `status`                    | `status`                   | `status` (varchar)            |
| Distance (km)          | `distance`                  | `distance_km`              | `distance_km` (float)         |
| Distance (meters)      | `distanceMeters`            | `distance_meters`          | `distance_meters` (numeric)   |
| Elevation Gain (m)     | `elevationGain`             | `elevation_gain_m`         | `elevation_gain_m` (float)    |
| Elevation Loss (m)     | `elevationLoss`             | `elevation_loss_m`         | `elevation_loss_m` (float)    |
| Calories Burned        | `caloriesBurned`            | `calories_burned`          | `calories_burned` (float)     |
| Avg Heart Rate         | `avgHeartRate`              | `avg_heart_rate`           | `avg_heart_rate` (int)        |

| Final Avg Pace         | `finalAveragePace`          | `final_average_pace`       | `final_average_pace` (numeric)|
| Final Distance (km)    | `finalDistanceKm`           | `final_distance_km`        | `final_distance_km` (numeric) |
| Final Calories Burned  | `finalCaloriesBurned`       | `final_calories_burned`    | `final_calories_burned` (int) |
| Final Elevation Gain   | `finalElevationGain`        | `final_elevation_gain`     | `final_elevation_gain` (numeric)|
| Final Elevation Loss   | `finalElevationLoss`        | `final_elevation_loss`     | `final_elevation_loss` (numeric)|
| Weight (kg)            | `weightKg`                  | `weight_kg`                | `weight_kg` (numeric)         |
| Ruck Weight (kg)       | `ruckWeightKg`              | `ruck_weight_kg`           | `ruck_weight_kg` (float)      |
| Notes                  | `notes`                     | `notes`                    | `notes` (text)                |
| Tags                   | `tags`                      | `tags`                     | `tags` (array)                |
| Rating                 | `rating`                    | `rating`                   | `rating` (int)                |
| Perceived Exertion     | `perceivedExertion`         | `perceived_exertion`       | `perceived_exertion` (int)    |
| Created At             | `createdAt`                 | `created_at`               | `created_at` (timestamp)      |
| Updated At             | `updatedAt`                 | `updated_at`               | `updated_at` (timestamp)      |

---

## Mapping Table

| Layer         | Example Name           | Notes                                 |
|---------------|-----------------------|---------------------------------------|
| Flutter/Dart  | `session.caloriesBurned` | Dart property, camelCase              |
| API (Python)  | `calories_burned`     | JSON field, snake_case                |
| Database      | `calories_burned`     | SQL column, snake_case                |

#### Example for Calories Burned
- **Frontend:** `session.caloriesBurned`
- **API Request/Response:** `"calories_burned": 1950`
- **Database:** `calories_burned` column in `ruck_sessions` table

---

## Detailed Database Schema: `ruck_sessions`

| Column Name                | Data Type                    | Nullable | Default                                      |
|----------------------------|------------------------------|----------|----------------------------------------------|
| id                         | integer                      | NO       | nextval('ruck_session_id_seq'::regclass)     |
| user_id                    | uuid                         | NO       |                                              |
| ruck_weight_kg             | double precision             | NO       |                                              |
| duration_seconds           | integer                      | YES      |                                              |
| paused_duration_seconds    | integer                      | YES      |                                              |
| final_average_pace         | numeric                      | YES      |                                              |
| rating                     | integer                      | YES      |                                              |
| perceived_exertion         | integer                      | YES      |                                              |
| distance_km                | double precision             | YES      |                                              |
| elevation_gain_m           | double precision             | YES      |                                              |
| elevation_loss_m           | double precision             | YES      |                                              |
| calories_burned            | double precision             | YES      |                                              |
| created_at                 | timestamp without time zone  | YES      |                                              |
| updated_at                 | timestamp without time zone  | YES      |                                              |
| planned_duration_minutes   | integer                      | YES      |                                              |
| started_at                 | timestamp with time zone     | YES      |                                              |
| ended_at                   | timestamp with time zone     | YES      |                                              |
| distance_meters            | numeric                      | YES      |                                              |
| weight_kg                  | numeric                      | YES      |                                              |
| completed_at               | timestamp with time zone     | YES      |                                              |
| final_distance_km          | numeric                      | YES      |                                              |
| final_calories_burned      | integer                      | YES      |                                              |
| final_elevation_gain       | numeric                      | YES      |                                              |
| final_elevation_loss       | numeric                      | YES      |                                              |
| status                     | character varying            | YES      |                                              |
| notes                      | text                         | YES      |                                              |
| tags                       | ARRAY                        | YES      |                                              |

---

## Detailed Database Schema: `users`

| Column Name     | Data Type                   | Nullable | Default |
|-----------------|-----------------------------|----------|---------|
| prefer_metric   | boolean                     | NO       | true    |
| created_at      | timestamp without time zone | YES      |         |
| updated_at      | timestamp without time zone | YES      |         |
| id              | uuid                        | NO       |         |
| weight_kg       | double precision            | YES      |         |
| username        | character varying           | NO       |         |
| email           | character varying           | NO       |         |
| password_hash   | character varying           | YES      |         |

### Property/API/DB Mapping: User

| Concept            | Dart/Flutter Property | API Field         | Database Column |
|--------------------|----------------------|-------------------|-----------------|
| User ID            | `id`                 | `id`              | `id`            |
| Username           | `username`           | `username`        | `username`      |
| Email              | `email`              | `email`           | `email`         |
| Password Hash      | `passwordHash`       | `password_hash`   | `password_hash` |
| Weight (kg)        | `weightKg`           | `weight_kg`       | `weight_kg`     |
| Prefer Metric      | `preferMetric`       | `prefer_metric`   | `prefer_metric` |
| Created At         | `createdAt`          | `created_at`      | `created_at`    |
| Updated At         | `updatedAt`          | `updated_at`      | `updated_at`    |

---

## Detailed Database Schema: `location_point`

| Column Name | Data Type                   | Nullable | Default                                   |
|-------------|-----------------------------|----------|-------------------------------------------|
| id          | integer                     | NO       | nextval('location_point_id_seq'::regclass) |
| session_id  | integer                     | NO       |                                           |
| latitude    | double precision            | NO       |                                           |
| longitude   | double precision            | NO       |                                           |
| altitude    | double precision            | YES      |                                           |
| timestamp   | timestamp without time zone | YES      |                                           |

### Property/API/DB Mapping: Location Point

| Concept       | Dart/Flutter Property | API Field      | Database Column |
|---------------|----------------------|----------------|-----------------|
| Point ID      | `id`                 | `id`           | `id`            |
| Session ID    | `sessionId`          | `session_id`   | `session_id`    |
| Latitude      | `latitude`           | `latitude`     | `latitude`      |
| Longitude     | `longitude`          | `longitude`    | `longitude`     |
| Altitude      | `altitude`           | `altitude`     | `altitude`      |
| Timestamp     | `timestamp`          | `timestamp`    | `timestamp`     |

---

## Detailed Database Schema: `heart_rate_sample`

| Column Name | Data Type                   | Nullable | Default                                      |
|-------------|-----------------------------|----------|----------------------------------------------|
| id          | integer                     | NO       | nextval('heart_rate_sample_id_seq'::regclass) |
| session_id  | integer                     | NO       |                                              |
| timestamp   | timestamp without time zone | NO       |                                              |
| bpm         | integer                     | NO       |                                              |

### Property/API/DB Mapping: Heart Rate Sample

| Concept       | Dart/Flutter Property | API Field      | Database Column |
|---------------|----------------------|----------------|-----------------|
| Sample ID     | `id`                 | `id`           | `id`            |
| Session ID    | `sessionId`          | `session_id`   | `session_id`    |
| Timestamp     | `timestamp`          | `timestamp`    | `timestamp`     |
| BPM           | `bpm`                | `bpm`          | `bpm`           |

---

## Example JSON Payload (API)

```json
{
  "ruck_id": "uuid-string",
  "user_id": "user-uuid",
  "start_time": "2025-05-07T09:00:00Z",
  "end_time": "2025-05-07T10:00:00Z",
  "duration_s": 3600,
  "distance_km": 10.13,
  "calories_burned": 1950,
  "elevation_gain_m": 80,
  "elevation_loss_m": 80,
  "ruck_weight_kg": 18.0,
  "notes": "Felt great!",
  "tags": ["morning", "urban"],
  "rating": 4,
  "perceived_exertion": 6,
  "avg_heart_rate": 128,
  "route_points": [{"lat": 40.41, "lng": -3.68, "timestamp": "..." }]
}
```

---

## Example SQL Table (`ruck_sessions`)

```sql
CREATE TABLE ruck_sessions (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_s INTEGER,
    distance_km FLOAT,
    calories_burned FLOAT,
    elevation_gain_m FLOAT,
    elevation_loss_m FLOAT,
    ruck_weight_kg FLOAT,
    notes TEXT,
    tags TEXT[], -- or JSONB if you want more structure
    rating INTEGER,
    perceived_exertion INTEGER,
    avg_heart_rate INTEGER,
    route_points JSONB
);
```

---

## Notes
- **Naming conventions:**  
  - Dart: camelCase  
  - API: snake_case  
  - DB: snake_case
- **Computed fields:** Some fields (like duration) may be computed on the API or frontend, but can also be stored for convenience.
- **Extensibility:** Add new fields as needed, but keep naming consistent across all layers.

---

If you want this for other entities (user, stats, etc.), or want to generate this directly from your codebase, just let me know! If you want me to check for mismatches or missing fields, I can do that too.

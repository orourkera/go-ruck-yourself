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
- [Session Splits](#session-splits)

---

## Session Properties

| Concept                | Dart/Flutter Property        | API Field (Python)         | Database Column (SQL)         |
|------------------------|-----------------------------|----------------------------|-------------------------------|
| Session ID             | `id`                        | `id`                       | `id` (PK, integer)            |
| User ID                | `userId`                    | `user_id`                  | `user_id` (FK, uuid)          |
| Start Time             | `startTime`                 | `start_time`               | `start_time` (timestamp)      |
| End Time (completion)  | `endTime`                   | `end_time`                 | `end_time` (timestamp)        |
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
| Avg Heart Rate         | `avgHeartRate`              | `avg_heart_rate`           | `avg_heart_rate` (integer, nullable)        |

| Average Pace (s/km)    | `averagePace`               | `average_pace`             | `average_pace` (numeric)      |
| Weight (kg)            | `weightKg`                  | `weight_kg`                | `weight_kg` (numeric)         |
| Ruck Weight (kg)       | `ruckWeightKg`              | `ruck_weight_kg`           | `ruck_weight_kg` (float)      |
| Notes                  | `notes`                     | `notes`                    | `notes` (text)                |
| Heart Rate Samples     | `heartRateSamples`          | `heart_rate_samples`        | `heart_rate_samples` (jsonb)  |
| Tags                   | `tags`                      | `tags`                     | `tags` (array)                |
| Public Session         | `isPublic`                 | `is_public`               | `is_public` (boolean, default false) |
| Rating                 | `rating`                   | `rating`                  | `rating` (int)              |
| Perceived Exertion     | `perceivedExertion`         | `perceived_exertion`       | `perceived_exertion` (int)    |
| Created At             | `createdAt`                 | `created_at`               | `created_at` (timestamp)      |
| Updated At             | `updatedAt`                 | `updated_at`               | `updated_at` (timestamp)      |

---

## SessionCompleteScreen Navigation Arguments

When navigating to the session completion screen, the following argument mapping is used from the Dart RuckSession model:

| Argument           | Dart Property             | Type                        | Notes                                   |
|--------------------|--------------------------|-----------------------------|-----------------------------------------|
| completedAt        | session.endTime           | DateTime                    | Required. Must be non-null.             |
| ruckId             | session.id                | String                      | Required. Must be non-null.             |
| duration           | session.duration          | Duration                    | Required. Must be non-null.             |
| distance           | session.distance          | double                      | Required. Must be non-null.             |
| caloriesBurned     | session.caloriesBurned    | int                         | Required. Must be non-null.             |
| elevationGain      | session.elevationGain     | double                      | Required. Must be non-null.             |
| elevationLoss      | session.elevationLoss     | double                      | Required. Must be non-null.             |
| ruckWeight         | session.ruckWeightKg      | double                      | Required. Must be non-null.             |
| initialNotes       | session.notes             | String?                     | Optional. Can be null.                  |
| heartRateSamples   | session.heartRateSamples  | List<HeartRateSample>?      | Optional. Can be null.                  |

> **Important:**
> - All argument keys must match exactly between navigation and the `SessionCompleteScreen` constructor.
> - Mismatches or missing required arguments will cause runtime errors or missing data.
> - See `active_session_page.dart` and `app.dart` for the current, canonical argument list.

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
- **Database:** `calories_burned` column in `ruck_session` table

---

> **Note:**
> - The `average_pace` value (seconds per kilometer) is now always included in the API and DB when saving a session, matching the Dart property `averagePace`.

## Detailed Database Schema: `ruck_session`

| Column Name                | Data Type                    | Nullable | Default                                      |
|---------------------------|------------------------------|----------|----------------------------------------------|
| id                        | integer                      | NO       | nextval('ruck_session_id_seq'::regclass)     |
| user_id                   | uuid                         | NO       |                                              |
| ruck_weight_kg            | double precision             | NO       |                                              |
| duration_seconds          | integer                      | YES      |                                              |
| paused_duration_seconds   | integer                      | YES      |                                              |
| status                    | character varying            | YES      |                                              |
| distance_km               | double precision             | YES      |                                              |
| elevation_gain_m          | double precision             | YES      |                                              |
| elevation_loss_m          | double precision             | YES      |                                              |
| calories_burned           | double precision             | YES      |                                              |
| created_at                | timestamp without time zone  | YES      |                                              |
| planned_duration_minutes  | integer                      | YES      |                                              |
| started_at                | timestamp with time zone     | YES      |                                              |
| distance_meters           | numeric                      | YES      |                                              |
| weight_kg                 | numeric                      | YES      |                                              |
| completed_at              | timestamp with time zone     | YES      |                                              |
| notes                     | text                         | YES      |                                              |
| average_pace              | numeric                      | YES      |                                              |
| avg_heart_rate            | integer                      | YES      |                                              |
| rating                    | integer                      | YES      |                                              |
| perceived_exertion        | integer                      | YES      |                                              |
| tags                      | ARRAY                        | YES      |                                              |

#### Timestamp Field Explanations:
*   **`created_at`**: Timestamp (without time zone) indicating when the session record was first created in the database. While present, its direct use in application logic is minimal. For all logical session timing and statistical bucketing, prefer `started_at` and `completed_at`.
*   **`started_at`**: Timestamp (with time zone) indicating when the user actively started the ruck. This is set by the application when the session begins.
*   **`completed_at`**: Timestamp (with time zone) indicating when the user actively completed or finalized the ruck. This is set by the application upon session completion. This is the primary timestamp used for all statistics aggregation (monthly, weekly, yearly) to determine which period a session falls into.

> **Note:** As of 2025-05-10, the following columns were removed from the schema because they are unused in the frontend and backend:
> - final_calories_burned
> - final_distance_km
> - final_elevation_gain
> - final_elevation_loss
> - ended_at
> - updated_at

---

## Detailed Database Schema: `user`

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
| Allow Ruck Sharing | `allowRuckSharing`   | `allow_ruck_sharing` | `allow_ruck_sharing` (boolean, default false) |
| Average Pace (s/km)| `averagePace`        | `average_pace`    | `average_pace`  |
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
| timestamp   | timestamp with time zone    | NO       |                                              |
| bpm         | integer                     | NO       |                                              |

### Property/API/DB Mapping: Heart Rate Sample

| Concept       | Dart/Flutter Property | API Field      | Database Column |
|---------------|----------------------|----------------|-----------------|
| Sample ID     | `id`                 | `id`           | `id`            |
| Session ID    | `sessionId`          | `session_id`   | `session_id`    |
| Timestamp     | `timestamp`          | `timestamp`    | `timestamp`     |
| BPM           | `bpm`                | `bpm`          | `bpm`           |

+**Real-time Streaming**: Heart rate samples are streamed from the Flutter client using POST `/rucks/{session_id}/heart_rate`. Each sample (timestamp + BPM) is stored individually in `heart_rate_sample`. Aggregations (e.g., average heart rate) are computed server-side or via SQL queries.
+
+**Client-side Rounding**: Numeric session metrics (distance, pace, calories, elevation, weight) are rounded client-side before sending: 
+- Distance values to 3 decimal places
+- Pace to 2 decimal places
+- Calories to nearest integer
+- Elevation gains/losses to nearest integer
+- Weights to one decimal place

---

## Detailed Database Schema: `session_splits`

| Column Name            | Data Type                   | Nullable | Default                                      |
|------------------------|-----------------------------|----------|----------------------------------------------|
| id                     | integer                     | NO       | nextval('session_splits_id_seq'::regclass) |
| session_id             | integer                     | NO       |                                              |
| split_number           | integer                     | NO       |                                              |
| split_distance_km      | numeric                     | NO       |                                              |
| split_duration_seconds | integer                     | NO       |                                              |
| total_distance_km      | numeric                     | NO       |                                              |
| total_duration_seconds | integer                     | NO       |                                              |
| split_timestamp        | timestamp with time zone    | NO       |                                              |
| created_at             | timestamp with time zone    | NO       | now()                                        |
| updated_at             | timestamp with time zone    | NO       | now()                                        |

### Property/API/DB Mapping: Session Splits

| Concept                | Dart/Flutter Property        | API Field                  | Database Column           |
|------------------------|------------------------------|----------------------------|---------------------------|
| Split ID               | `id`                         | `id`                       | `id`                      |
| Session ID             | `sessionId`                  | `session_id`               | `session_id`              |
| Split Number           | `splitNumber`                | `split_number`             | `split_number`            |
| Split Distance (km)    | `splitDistanceKm`            | `split_distance_km`        | `split_distance_km`       |
| Split Duration (s)     | `splitDurationSeconds`       | `split_duration_seconds`   | `split_duration_seconds`  |
| Total Distance (km)    | `totalDistanceKm`            | `total_distance_km`        | `total_distance_km`       |
| Total Duration (s)     | `totalDurationSeconds`       | `total_duration_seconds`   | `total_duration_seconds`  |
| Split Timestamp        | `splitTimestamp`             | `split_timestamp`          | `split_timestamp`         |
| Created At             | `createdAt`                  | `created_at`               | `created_at`              |
| Updated At             | `updatedAt`                  | `updated_at`               | `updated_at`              |

**Split Tracking**: Session splits represent 1km or 1mi milestones during a ruck session. Each split records the time taken to complete that segment, along with cumulative totals. Split distance is stored in kilometers regardless of user preference (1.0km for metric users, 1.609km for imperial users who complete 1 mile).

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

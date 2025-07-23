# Database Index Reference - Ruck App

**Last Updated:** July 23, 2025  
**Purpose:** Complete reference of all existing database indexes to prevent duplicate suggestions

## Performance-Critical Tables & Indexes

### ruck_session (Primary data table)
- `ruck_session_pkey`: PRIMARY KEY (id)
- `idx_ruck_session_user_id`: user_id
- `idx_ruck_session_user_completed`: user_id, completed_at DESC
- `idx_ruck_session_user_completed_status`: user_id, completed_at DESC, status
- `idx_ruck_session_user_started`: user_id, started_at DESC
- `idx_ruck_session_user_status`: user_id, status
- `idx_ruck_session_status`: status
- `idx_ruck_session_public_completed`: is_public, completed_at DESC WHERE is_public = true
- `idx_ruck_session_monthly_stats`: user_id, status, completed_at DESC WHERE status = 'completed'
- `idx_ruck_session_power_points`: power_points WHERE status = 'completed'
- `idx_ruck_session_event`: event_id
- `idx_ruck_session_is_manual`: is_manual

### location_point (Partitioned by month)
**Parent Table:**
- `location_point_partitioned_pkey`: PRIMARY KEY (id, timestamp)
- `idx_location_point_part_session`: session_id
- `idx_location_point_part_session_time`: session_id, timestamp
- `idx_location_point_coords`: latitude, longitude

**Per-Partition Indexes (202505-202512):**
- `location_point_YYYYMM_pkey`: PRIMARY KEY (id, timestamp)
- `location_point_YYYYMM_session_id_idx`: session_id
- `location_point_YYYYMM_session_id_timestamp_idx`: session_id, timestamp
- `location_point_YYYYMM_latitude_longitude_idx`: latitude, longitude

### user (User management)
- `user_pkey`: PRIMARY KEY (id)
- `user_email_key`: UNIQUE (email)
- `unique_user_email`: UNIQUE (email)
- `idx_users_last_active_at`: last_active_at
- `idx_user_allow_ruck_sharing`: allow_ruck_sharing WHERE allow_ruck_sharing = true
- `idx_user_profile_private`: is_profile_private
- `idx_user_notification_preferences`: notification_clubs, notification_buddies, notification_events, notification_duels

## Social Features

### user_follows (Social connections)
- `user_follows_pkey`: PRIMARY KEY (id)
- `user_follows_follower_id_followed_id_key`: UNIQUE (follower_id, followed_id)
- `idx_user_follows_follower_id`: follower_id
- `idx_user_follows_followed_id`: followed_id
- `idx_user_follows_follower`: follower_id
- `idx_user_follows_followed`: followed_id
- `idx_user_follows_follower_created`: follower_id, created_at DESC
- `idx_user_follows_followed_created`: followed_id, created_at DESC
- `idx_user_follows_follower_followed`: follower_id, followed_id
- `idx_user_follows_created_at`: created_at

### ruck_likes (Social engagement)
- `ruck_likes_pkey`: PRIMARY KEY (id)
- `ruck_likes_ruck_id_user_id_key`: UNIQUE (ruck_id, user_id)
- `idx_ruck_likes_ruck_id`: ruck_id
- `idx_ruck_likes_user_id`: user_id

### ruck_comments
- `ruck_comments_pkey`: PRIMARY KEY (id)
- `idx_ruck_comments_ruck_id`: ruck_id
- `idx_ruck_comments_user_id`: user_id

### ruck_photos
- `ruck_photos_pkey`: PRIMARY KEY (id)
- `idx_ruck_photos_ruck_id`: ruck_id
- `idx_ruck_photos_user_id`: user_id

## Achievements System

### achievements (Master definitions)
- `achievements_pkey`: PRIMARY KEY (id)
- `achievements_achievement_key_key`: UNIQUE (achievement_key)
- `idx_achievements_key`: achievement_key
- `idx_achievements_active`: is_active
- `idx_achievements_is_active`: is_active
- `idx_achievements_active_unit`: is_active, unit_preference
- `idx_achievements_category`: category
- `idx_achievements_category_tier`: category, tier WHERE is_active = true
- `idx_achievements_criteria`: criteria (GIN index)

### user_achievements (User earned achievements)
- `user_achievements_pkey`: PRIMARY KEY (id)
- `user_achievements_user_id_achievement_id_key`: UNIQUE (user_id, achievement_id)
- `idx_user_achievements_user_id`: user_id
- `idx_user_achievements_earned_at`: earned_at
- `idx_user_achievements_recent`: earned_at DESC
- `idx_user_achievements_user_earned`: user_id, earned_at DESC

### achievement_progress (Progress tracking)
- `achievement_progress_pkey`: PRIMARY KEY (id)
- `achievement_progress_user_id_achievement_id_key`: UNIQUE (user_id, achievement_id)
- `idx_achievement_progress_user_id`: user_id
- `idx_achievement_progress_current_value`: current_value DESC
- `idx_achievement_progress_completion`: user_id, current_value, target_value
- `idx_achievement_progress_user_updated`: user_id, last_updated DESC

## Events System

### events (Event management)
- `events_pkey`: PRIMARY KEY (id)
- `idx_events_creator`: creator_user_id
- `idx_events_creator_status`: creator_user_id, status
- `idx_events_club`: club_id
- `idx_events_club_id_scheduled`: club_id, scheduled_start_time
- `idx_events_start_time`: scheduled_start_time
- `idx_events_status`: status
- `idx_events_location`: latitude, longitude

### event_participants
- `event_participants_pkey`: PRIMARY KEY (id)
- `event_participants_event_id_user_id_key`: UNIQUE (event_id, user_id)
- `idx_event_participants_event`: event_id, status
- `idx_event_participants_user`: user_id, status
- `idx_event_participants_status`: status

### event_participant_progress
- `event_participant_progress_pkey`: PRIMARY KEY (id)
- `event_participant_progress_event_id_user_id_key`: UNIQUE (event_id, user_id)
- `idx_event_progress_event`: event_id
- `idx_event_progress_user`: user_id
- `idx_event_progress_session`: ruck_session_id
- `idx_event_progress_status`: status

### event_comments
- `event_comments_pkey`: PRIMARY KEY (id)
- `idx_event_comments_event`: event_id
- `idx_event_comments_user`: user_id
- `idx_event_comments_created`: created_at

## Duels System

### duels (Duel management)
- `duels_pkey`: PRIMARY KEY (id)
- `idx_duels_creator_id`: creator_id
- `idx_duels_status`: status
- `idx_duels_created_at`: created_at DESC
- `idx_duels_ends_at`: ends_at
- `idx_duels_is_public`: is_public
- `idx_duels_challenge_type`: challenge_type
- `idx_duels_start_mode`: start_mode
- `idx_duels_status_dates`: status, starts_at, ends_at

### duel_participants
- `duel_participants_pkey`: PRIMARY KEY (id)
- `duel_participants_duel_id_user_id_key`: UNIQUE (duel_id, user_id)
- `idx_duel_participants_duel_id`: duel_id
- `idx_duel_participants_user_id`: user_id
- `idx_duel_participants_status`: status
- `idx_duel_participants_current_value`: current_value DESC

### duel_sessions
- `duel_sessions_pkey`: PRIMARY KEY (id)
- `duel_sessions_duel_id_session_id_key`: UNIQUE (duel_id, session_id)
- `idx_duel_sessions_duel_id`: duel_id
- `idx_duel_sessions_session_id`: session_id
- `idx_duel_sessions_participant_id`: participant_id
- `idx_duel_sessions_created_at`: created_at DESC

### duel_comments
- `duel_comments_pkey`: PRIMARY KEY (id)
- `idx_duel_comments_duel_id`: duel_id
- `idx_duel_comments_user_id`: user_id
- `idx_duel_comments_created_at`: created_at DESC

### duel_invitations
- `duel_invitations_pkey`: PRIMARY KEY (id)
- `duel_invitations_duel_id_invitee_email_key`: UNIQUE (duel_id, invitee_email)
- `idx_duel_invitations_duel_id`: duel_id
- `idx_duel_invitations_inviter_id`: inviter_id
- `idx_duel_invitations_invitee_email`: invitee_email
- `idx_duel_invitations_status`: status
- `idx_duel_invitations_expires_at`: expires_at

## Clubs System

### clubs
- `clubs_pkey`: PRIMARY KEY (id)
- `idx_clubs_location`: latitude, longitude

### club_memberships
- `club_memberships_pkey`: PRIMARY KEY (id)
- `club_memberships_club_id_user_id_key`: UNIQUE (club_id, user_id)
- `idx_club_memberships_club_status`: club_id, status
- `idx_club_memberships_user_status`: user_id, status

## Notifications System

### notifications (Push & in-app notifications)
- `notifications_pkey`: PRIMARY KEY (id)
- `idx_notifications_recipient_created`: recipient_id, created_at DESC
- `idx_notifications_recipient_unread`: recipient_id, is_read, created_at DESC
- `idx_notifications_recipient_read_at`: recipient_id, read_at DESC
- `idx_notifications_sender_created`: sender_id, created_at DESC
- `idx_notifications_unread`: recipient_id, is_read
- `idx_notifications_type`: type
- `idx_notifications_club_id`: club_id
- `idx_notifications_event_id`: event_id
- `idx_notifications_club`: club_id, created_at DESC WHERE club_id IS NOT NULL
- `idx_notifications_event`: event_id, created_at DESC WHERE event_id IS NOT NULL
- `idx_notifications_duel`: duel_id, created_at DESC WHERE duel_id IS NOT NULL

## Session Analytics

### heart_rate_sample
- `heart_rate_sample_pkey`: PRIMARY KEY (id)
- `ix_heart_rate_sample_session_id`: session_id

### session_splits
- `session_splits_pkey`: PRIMARY KEY (id)
- `session_splits_unique_split`: UNIQUE (session_id, split_number)
- `idx_session_splits_session_id`: session_id
- `idx_session_splits_split_timestamp`: split_timestamp

### session_review
- `session_review_pkey`: PRIMARY KEY (id)
- `session_review_session_id_key`: UNIQUE (session_id)

## User Statistics

### user_duel_stats
- `user_duel_stats_pkey`: PRIMARY KEY (id)
- `user_duel_stats_user_id_key`: UNIQUE (user_id)
- `idx_user_duel_stats_user_id`: user_id
- `idx_user_duel_stats_duels_won`: duels_won DESC
- `idx_user_duel_stats_duels_completed`: duels_completed DESC

### user_profile_stats
- `user_profile_stats_pkey`: PRIMARY KEY (user_id)

## Device Management

### user_device_tokens (Push notifications)
- `user_device_tokens_pkey`: PRIMARY KEY (id)
- `user_device_tokens_user_id_device_id_key`: UNIQUE (user_id, device_id)
- `idx_user_device_tokens_user_id`: user_id
- `idx_user_device_tokens_fcm_token`: fcm_token
- `idx_user_device_tokens_active`: is_active WHERE is_active = true

## System Tables

### alembic_version (Database migrations)
- `alembic_version_pkc`: PRIMARY KEY (version_num)

### hubspot_sync_log (External integrations)
- `hubspot_sync_log_pkey`: PRIMARY KEY (id)

### spatial_ref_sys (PostGIS)
- `spatial_ref_sys_pkey`: PRIMARY KEY (srid)

### location_point_old_backup (Archived data)
- `location_point_pkey`: PRIMARY KEY (id)
- `idx_location_point_session_id`: session_id
- `idx_location_point_session_timestamp`: session_id, timestamp DESC

---

## Index Usage Guidelines

### BEFORE suggesting new indexes, check:
1. **Table coverage**: Is the table already well-indexed?
2. **Column combinations**: Do similar composite indexes already exist?
3. **Query patterns**: Are the existing indexes sufficient for common queries?
4. **Partial indexes**: Can existing partial indexes be used instead?

### High-performance areas already covered:
- ✅ User session queries (multiple user_id + status/date combinations)
- ✅ Social features (follows, likes, comments all indexed)
- ✅ Location data (partitioned with session_id and coordinate indexes)
- ✅ Achievements (comprehensive user/category/tier indexing)
- ✅ Events (club, creator, status, date combinations)
- ✅ Duels (participant, status, date combinations)
- ✅ Notifications (recipient, sender, type, entity-specific)

### Index Statistics:
- **Total Indexes**: 232
- **Unique Indexes**: 35
- **Partial Indexes**: 12
- **GIN Indexes**: 1 (achievements criteria)
- **Partitioned Table Indexes**: 32 (location_point partitions)

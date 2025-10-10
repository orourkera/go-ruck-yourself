-- Fix streak calculation in user_insights
-- This adds proper daily streak calculation to the compute_user_facts function

CREATE OR REPLACE FUNCTION compute_user_facts(u_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  prefer_metric BOOLEAN := TRUE;
  now_utc TIMESTAMPTZ := NOW();
  facts JSONB := '{}'::jsonb;
  current_streak INT := 0;
  longest_streak INT := 0;
BEGIN
  -- Pull preference and simple profile
  SELECT COALESCE(prefer_metric, TRUE)
    INTO prefer_metric
  FROM "user"
  WHERE id = u_id
  LIMIT 1;

  -- Calculate daily streak
  WITH session_dates AS (
    SELECT DISTINCT DATE(completed_at AT TIME ZONE 'UTC') as session_date
    FROM ruck_session
    WHERE user_id = u_id
      AND status = 'completed'
      AND COALESCE(duration_seconds, 0) >= 300
    ORDER BY session_date DESC
  ),
  streak_calc AS (
    SELECT
      session_date,
      session_date - (ROW_NUMBER() OVER (ORDER BY session_date DESC))::INT * INTERVAL '1 day' as streak_group
    FROM session_dates
  ),
  streak_groups AS (
    SELECT
      streak_group,
      COUNT(*) as streak_length,
      MAX(session_date) as last_date,
      MIN(session_date) as first_date
    FROM streak_calc
    GROUP BY streak_group
  ),
  current_streak_calc AS (
    -- Check if the most recent streak includes today or yesterday
    SELECT
      CASE
        WHEN MAX(last_date) >= CURRENT_DATE - INTERVAL '1 day' THEN MAX(streak_length)
        ELSE 0
      END as current_streak
    FROM streak_groups
    WHERE last_date >= CURRENT_DATE - INTERVAL '1 day'
  ),
  max_streak AS (
    SELECT COALESCE(MAX(streak_length), 0) as longest_streak
    FROM streak_groups
  )
  SELECT
    COALESCE((SELECT current_streak FROM current_streak_calc), 0),
    COALESCE((SELECT longest_streak FROM max_streak), 0)
  INTO current_streak, longest_streak;

  -- Totals (30/90 days) and recency
  WITH recent AS (
    SELECT * FROM ruck_session
    WHERE user_id = u_id
      AND status = 'completed'
      AND COALESCE(duration_seconds, 0) >= 300
  )
  , span30 AS (
    SELECT COALESCE(SUM(distance_km),0) AS dist_km,
           COALESCE(SUM(elevation_gain_m),0) AS elev_m,
           COALESCE(SUM(duration_seconds),0) AS dur_s,
           COUNT(*) AS sessions
    FROM recent WHERE completed_at >= now_utc - INTERVAL '30 days'
  )
  , span90 AS (
    SELECT COALESCE(SUM(distance_km),0) AS dist_km,
           COALESCE(SUM(elevation_gain_m),0) AS elev_m,
           COALESCE(SUM(duration_seconds),0) AS dur_s,
           COUNT(*) AS sessions
    FROM recent WHERE completed_at >= now_utc - INTERVAL '90 days'
  )
  , last_done AS (
    SELECT completed_at, distance_km, ruck_weight_kg
    FROM recent
    ORDER BY completed_at DESC
    LIMIT 1
  )
  , last_weighted AS (
    SELECT completed_at, ruck_weight_kg
    FROM recent
    WHERE ruck_weight_kg IS NOT NULL AND ruck_weight_kg > 0
    ORDER BY completed_at DESC
    LIMIT 1
  )
  , load_stats AS (
    SELECT
      AVG(NULLIF(ruck_weight_kg, 0)) AS avg_weight_kg,
      COUNT(*) FILTER (WHERE ruck_weight_kg IS NOT NULL AND ruck_weight_kg > 0) AS sessions_with_weight
    FROM recent
  )
  , all_time AS (
    SELECT COALESCE(SUM(distance_km),0) AS dist_km,
           COALESCE(SUM(elevation_gain_m),0) AS elev_m,
           COUNT(*) AS sessions
    FROM recent
  )
  SELECT jsonb_build_object(
    'prefer_metric', prefer_metric,
    'average_ruck_weight_kg', COALESCE((SELECT avg_weight_kg FROM load_stats), 0),
    'sessions_with_weight', COALESCE((SELECT sessions_with_weight FROM load_stats), 0),
    'current_streak_days', current_streak,
    'longest_streak_days', longest_streak,
    'totals_30d', jsonb_build_object(
      'distance_km', COALESCE(span30.dist_km,0),
      'elevation_m', COALESCE(span30.elev_m,0),
      'duration_s', COALESCE(span30.dur_s,0),
      'sessions', COALESCE(span30.sessions,0)
    ),
    'totals_90d', jsonb_build_object(
      'distance_km', COALESCE(span90.dist_km,0),
      'elevation_m', COALESCE(span90.elev_m,0),
      'duration_s', COALESCE(span90.dur_s,0),
      'sessions', COALESCE(span90.sessions,0)
    ),
    'recency', jsonb_build_object(
      'last_completed_at', (SELECT completed_at FROM last_done),
      'days_since_last', CASE WHEN (SELECT completed_at FROM last_done) IS NULL THEN NULL
                              ELSE EXTRACT(EPOCH FROM (now_utc - (SELECT completed_at FROM last_done)))/86400 END,
      'last_ruck_distance_km', (SELECT distance_km FROM last_done),
      'last_ruck_weight_kg', COALESCE((SELECT ruck_weight_kg FROM last_weighted), (SELECT ruck_weight_kg FROM last_done))
    ),
    'all_time', jsonb_build_object(
      'distance_km', COALESCE(all_time.dist_km,0),
      'elevation_m', COALESCE(all_time.elev_m,0),
      'sessions', COALESCE(all_time.sessions,0)
    )
  )
  INTO facts
  FROM span30, span90, last_done, all_time;

  -- Aggregate splits: average pace by split index (first 10), negative split frequency (last split faster than first)
  WITH recent_sessions AS (
    SELECT id, completed_at
    FROM ruck_session
    WHERE user_id = u_id
      AND status = 'completed'
      AND COALESCE(duration_seconds, 0) >= 300
    ORDER BY completed_at DESC
    LIMIT 100
  ),
  norm_splits AS (
    SELECT s.session_id,
           s.split_number AS idx,
           -- per-split distance/time from total_* deltas where available
           (s.total_distance_km::float - COALESCE(LAG(s.total_distance_km::float) OVER (PARTITION BY s.session_id ORDER BY s.split_number), 0)) AS split_dist_km,
           (s.total_duration_seconds - COALESCE(LAG(s.total_duration_seconds) OVER (PARTITION BY s.session_id ORDER BY s.split_number), 0)) AS split_time_s,
           s.total_duration_seconds,
           s.total_distance_km
    FROM session_splits s
    JOIN recent_sessions rs ON rs.id = s.session_id
  ),
  split_core AS (
    SELECT *,
           CASE WHEN split_dist_km > 0 THEN split_time_s / split_dist_km ELSE NULL END AS pace_s_per_km
    FROM norm_splits
  ),
  first10 AS (
    SELECT idx, AVG(pace_s_per_km) AS avg_pace_s_per_km, STDDEV_POP(pace_s_per_km) AS std_pace_s_per_km
    FROM split_core
    WHERE idx BETWEEN 1 AND 10 AND pace_s_per_km IS NOT NULL AND split_time_s > 0
    GROUP BY idx
    ORDER BY idx
  ),
  negative_split_freq AS (
    SELECT sc.session_id,
           FIRST_VALUE(pace_s_per_km) OVER (PARTITION BY sc.session_id ORDER BY idx ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_pace,
           LAST_VALUE(pace_s_per_km) OVER (PARTITION BY sc.session_id ORDER BY idx ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_pace
    FROM split_core sc
  ),
  neg_summary AS (
    SELECT AVG(CASE WHEN last_pace IS NOT NULL AND first_pace IS NOT NULL AND last_pace < first_pace THEN 1.0 ELSE 0.0 END) AS negative_split_ratio
    FROM (
      SELECT DISTINCT session_id, first_pace, last_pace FROM negative_split_freq
    ) t
  )
  SELECT facts
         || jsonb_build_object('splits', jsonb_build_object(
              'avg_pace_s_per_km_by_idx_1_10', COALESCE(
                  (SELECT jsonb_agg(jsonb_build_object('idx', idx, 'avg', avg_pace_s_per_km, 'std', std_pace_s_per_km) ORDER BY idx) FROM first10), '[]'::jsonb),
              'negative_split_frequency', COALESCE((SELECT negative_split_ratio FROM neg_summary), 0)
            ))
  INTO facts;

  -- Recent splits sample: last 3 sessions with at most 40 splits each
  WITH last3 AS (
    SELECT id, completed_at
    FROM ruck_session
    WHERE user_id = u_id
      AND status='completed'
      AND COALESCE(duration_seconds, 0) >= 300
    ORDER BY completed_at DESC
    LIMIT 3
  ),
  sample AS (
    SELECT s.session_id,
           s.split_number AS idx,
           (s.total_distance_km::float - COALESCE(LAG(s.total_distance_km::float) OVER (PARTITION BY s.session_id ORDER BY s.split_number), 0)) AS split_dist_km,
           (s.total_duration_seconds - COALESCE(LAG(s.total_duration_seconds) OVER (PARTITION BY s.session_id ORDER BY s.split_number), 0)) AS split_time_s,
           s.total_duration_seconds,
           s.total_distance_km
    FROM session_splits s
    JOIN last3 l ON l.id = s.session_id
    WHERE s.split_number <= 40
    ORDER BY s.session_id, s.split_number
  )
  SELECT facts
         || jsonb_build_object('recent_splits', COALESCE(
              (
                SELECT jsonb_agg(sess ORDER BY (sess->>'completed_at')::timestamptz DESC)
                FROM (
                  SELECT jsonb_build_object(
                    'session_id', l.id,
                    'completed_at', l.completed_at,
                    'splits', (
                      SELECT jsonb_agg(jsonb_build_object(
                        'idx', idx,
                        'distance_km', split_dist_km,
                        'time_s', split_time_s,
                        'pace_s_per_km', CASE WHEN split_dist_km > 0 THEN split_time_s / split_dist_km ELSE NULL END
                      ) ORDER BY idx)
                      FROM sample s WHERE s.session_id = l.id
                    )
                  ) AS sess
                  FROM last3 l
                ) q
              ), '[]'::jsonb)
            )
  INTO facts;

  -- Achievements summary (recent 10)
  WITH ua AS (
    SELECT ua.achievement_id, ua.earned_at, a.name, a.achievement_key
    FROM user_achievements ua
    JOIN achievements a ON a.id = ua.achievement_id
    WHERE ua.user_id = u_id
    ORDER BY ua.earned_at DESC
    LIMIT 10
  )
  SELECT facts
         || jsonb_build_object('achievements_recent', COALESCE(
              (SELECT jsonb_agg(jsonb_build_object(
                'achievement_id', achievement_id,
                'key', achievement_key,
                'name', name,
                'earned_at', earned_at
              )) FROM ua), '[]'::jsonb))
  INTO facts;

  -- Calculate aggregated insights to flatten data for easier consumption
  WITH aggregated_insights AS (
    SELECT
      -- Total stats
      (SELECT COALESCE(COUNT(*), 0) FROM ruck_session WHERE user_id = u_id AND status = 'completed') as total_sessions,
      (SELECT COALESCE(SUM(distance_km), 0) FROM ruck_session WHERE user_id = u_id AND status = 'completed') as total_distance_km,
      (SELECT COALESCE(SUM(duration_seconds) / 3600.0, 0) FROM ruck_session WHERE user_id = u_id AND status = 'completed') as total_duration_hours,
      (SELECT COALESCE(AVG(CASE WHEN distance_km > 0 THEN (duration_seconds / 60.0) / distance_km * 60 ELSE NULL END), 0)
       FROM ruck_session WHERE user_id = u_id AND status = 'completed') as avg_pace_per_km_seconds,
      (SELECT COALESCE(SUM(elevation_gain_m), 0) FROM ruck_session WHERE user_id = u_id AND status = 'completed') as total_elevation_gain_m,

      -- Recent stats (last 30 days)
      (SELECT COALESCE(COUNT(*), 0) FROM ruck_session WHERE user_id = u_id AND status = 'completed' AND completed_at >= now_utc - INTERVAL '30 days') as recent_sessions_count,
      (SELECT COALESCE(AVG(distance_km), 0) FROM ruck_session WHERE user_id = u_id AND status = 'completed' AND completed_at >= now_utc - INTERVAL '30 days') as recent_avg_distance_km,
      (SELECT COALESCE(AVG(CASE WHEN distance_km > 0 THEN (duration_seconds / 60.0) / distance_km * 60 ELSE NULL END), 0)
       FROM ruck_session WHERE user_id = u_id AND status = 'completed' AND completed_at >= now_utc - INTERVAL '30 days') as recent_avg_pace_per_km_seconds,

      -- Achievements
      (SELECT COALESCE(COUNT(*), 0) FROM user_achievements WHERE user_id = u_id) as achievements_total,
      (SELECT COALESCE(COUNT(*), 0) FROM user_achievements WHERE user_id = u_id AND earned_at >= now_utc - INTERVAL '30 days') as achievements_recent,

      -- Streaks (already calculated above)
      current_streak as current_streak_days,
      longest_streak as longest_streak_days
  )
  SELECT facts || to_jsonb(aggregated_insights) INTO facts FROM aggregated_insights;

  RETURN facts;
END;
$$;
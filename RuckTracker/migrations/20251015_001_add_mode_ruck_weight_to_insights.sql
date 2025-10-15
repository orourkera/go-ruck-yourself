-- Migration: Add mode (most common) ruck weight to user insights
-- Author: Claude 2025-10-15
-- Purpose: Calculate and include the most frequently used ruck weight

CREATE OR REPLACE FUNCTION compute_user_facts(u_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  prefer_metric BOOLEAN := TRUE;
  now_utc TIMESTAMPTZ := NOW();
  facts JSONB := '{}'::jsonb;
  temp_facts JSONB;
BEGIN
  -- Defensive check: ensure user exists
  IF NOT EXISTS (SELECT 1 FROM "user" WHERE id = u_id) THEN
    RETURN jsonb_build_object(
      'error', 'user_not_found',
      'prefer_metric', true,
      'totals_30d', jsonb_build_object('distance_km', 0, 'elevation_m', 0, 'duration_s', 0, 'sessions', 0),
      'totals_90d', jsonb_build_object('distance_km', 0, 'elevation_m', 0, 'duration_s', 0, 'sessions', 0),
      'all_time', jsonb_build_object('distance_km', 0, 'elevation_m', 0, 'sessions', 0),
      'recency', jsonb_build_object('last_completed_at', null, 'days_since_last', null),
      'recent_splits', '[]'::jsonb,
      'achievements_recent', '[]'::jsonb
    );
  END IF;

  -- Pull preference and simple profile
  SELECT COALESCE(u.prefer_metric, TRUE) INTO prefer_metric FROM "user" u WHERE u.id = u_id LIMIT 1;

  -- Build base facts with defensive NULL checking
  BEGIN
    WITH span30 AS (
      SELECT SUM(distance_km) as dist_km, SUM(elevation_gain_m) as elev_m, SUM(duration_seconds) as dur_s, COUNT(*) as sessions
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
        AND completed_at >= now_utc - INTERVAL '30 days'
    ),
    span90 AS (
      SELECT SUM(distance_km) as dist_km, SUM(elevation_gain_m) as elev_m, SUM(duration_seconds) as dur_s, COUNT(*) as sessions
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
        AND completed_at >= now_utc - INTERVAL '90 days'
    ),
    all_time AS (
      SELECT SUM(distance_km) as dist_km, SUM(elevation_gain_m) as elev_m, COUNT(*) as sessions
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
    ),
    last_done AS (
      SELECT completed_at, distance_km, ruck_weight_kg
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
      ORDER BY completed_at DESC
      LIMIT 1
    ),
    last_weighted AS (
      SELECT completed_at, ruck_weight_kg
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
        AND ruck_weight_kg IS NOT NULL AND ruck_weight_kg > 0
      ORDER BY completed_at DESC
      LIMIT 1
    ),
    load_stats AS (
      SELECT
        AVG(NULLIF(ruck_weight_kg, 0)) AS avg_weight_kg,
        COUNT(*) FILTER (WHERE ruck_weight_kg IS NOT NULL AND ruck_weight_kg > 0) AS sessions_with_weight
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
    ),
    mode_weight AS (
      -- Calculate mode (most frequent) ruck weight
      SELECT ruck_weight_kg as mode_weight_kg
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND ruck_weight_kg IS NOT NULL AND ruck_weight_kg > 0
        AND COALESCE(duration_seconds, 0) >= 300
      GROUP BY ruck_weight_kg
      ORDER BY COUNT(*) DESC, ruck_weight_kg DESC  -- Prefer heavier weight if tie
      LIMIT 1
    )
    SELECT jsonb_build_object(
      'prefer_metric', prefer_metric,
      'average_ruck_weight_kg', COALESCE(load_stats.avg_weight_kg, 0),
      'mode_ruck_weight_kg', COALESCE(mode_weight.mode_weight_kg, 0),
      'sessions_with_weight', COALESCE(load_stats.sessions_with_weight, 0),
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
        'last_ruck_weight_kg', COALESCE((SELECT ruck_weight_kg FROM last_weighted), (SELECT ruck_weight_kg FROM last_done)),
        'last_nonzero_ruck_weight_kg', (SELECT ruck_weight_kg FROM last_weighted)
      ),
      'all_time', jsonb_build_object(
        'distance_km', COALESCE(all_time.dist_km,0),
        'elevation_m', COALESCE(all_time.elev_m,0),
        'sessions', COALESCE(all_time.sessions,0)
      )
    )
    INTO temp_facts
    FROM span30, span90, last_done, all_time, load_stats, mode_weight;

    -- Only update facts if we got a valid result
    IF temp_facts IS NOT NULL THEN
      facts := temp_facts;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    -- Log error but continue with base facts
    RAISE WARNING 'compute_user_facts base aggregation failed for user %: %', u_id, SQLERRM;
  END;

  -- Add recent splits with defensive error handling
  BEGIN
    WITH recent_sessions AS (
      SELECT id, completed_at
      FROM ruck_session
      WHERE user_id = u_id AND status = 'completed'
        AND COALESCE(duration_seconds, 0) >= 300
      ORDER BY completed_at DESC
      LIMIT 100
    ),
    last3 AS (
      SELECT id, completed_at FROM recent_sessions ORDER BY completed_at DESC LIMIT 3
    ),
    sample AS (
      SELECT s.session_id, s.split_number AS idx, s.split_distance_km, s.split_time_s
      FROM session_splits s
      JOIN last3 l ON l.id = s.session_id
      WHERE s.split_number <= 40
      ORDER BY s.session_id, s.split_number
    )
    SELECT facts || jsonb_build_object('recent_splits', COALESCE(
      (
        SELECT jsonb_agg(sess ORDER BY (sess->>'completed_at')::timestamptz DESC)
        FROM (
          SELECT jsonb_build_object(
            'session_id', l.id,
            'completed_at', l.completed_at,
            'splits', (
              SELECT jsonb_agg(jsonb_build_object(
                'idx', idx,
                'distance_km', split_distance_km,
                'time_s', split_time_s,
                'pace_s_per_km', CASE WHEN split_distance_km > 0 THEN split_time_s / split_distance_km ELSE NULL END
              ) ORDER BY idx)
              FROM sample s WHERE s.session_id = l.id
            )
          ) AS sess
          FROM last3 l
        ) q
      ), '[]'::jsonb)
    )
    INTO temp_facts;

    IF temp_facts IS NOT NULL THEN
      facts := temp_facts;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    -- Add empty splits array on error
    RAISE WARNING 'compute_user_facts splits calculation failed for user %: %', u_id, SQLERRM;
    facts := facts || jsonb_build_object('recent_splits', '[]'::jsonb);
  END;

  -- Add achievements with defensive error handling
  BEGIN
    WITH ua AS (
      SELECT ua.achievement_id, ua.earned_at, a.name, a.achievement_key
      FROM user_achievements ua
      JOIN achievements a ON a.id = ua.achievement_id
      WHERE ua.user_id = u_id
      ORDER BY ua.earned_at DESC
      LIMIT 10
    )
    SELECT facts || jsonb_build_object('achievements_recent', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'achievement_id', achievement_id,
        'key', achievement_key,
        'name', name,
        'earned_at', earned_at
      )) FROM ua), '[]'::jsonb))
    INTO temp_facts;

    IF temp_facts IS NOT NULL THEN
      facts := temp_facts;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    -- Add empty achievements array on error
    RAISE WARNING 'compute_user_facts achievements calculation failed for user %: %', u_id, SQLERRM;
    facts := facts || jsonb_build_object('achievements_recent', '[]'::jsonb);
  END;

  -- Final safety check - should never be null
  IF facts IS NULL THEN
    RAISE WARNING 'compute_user_facts returning null for user %, using fallback', u_id;
    RETURN jsonb_build_object(
      'error', 'computation_failed',
      'prefer_metric', prefer_metric,
      'totals_30d', jsonb_build_object('distance_km', 0, 'elevation_m', 0, 'duration_s', 0, 'sessions', 0),
      'totals_90d', jsonb_build_object('distance_km', 0, 'elevation_m', 0, 'duration_s', 0, 'sessions', 0),
      'all_time', jsonb_build_object('distance_km', 0, 'elevation_m', 0, 'sessions', 0),
      'recency', jsonb_build_object('last_completed_at', null, 'days_since_last', null),
      'recent_splits', '[]'::jsonb,
      'achievements_recent', '[]'::jsonb
    );
  END IF;

  RETURN facts;
END;
$$;

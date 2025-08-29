-- Create user_insights table to store nightly/on-completion snapshots
-- Hybrid design: structured columns + JSONB payloads

CREATE TABLE IF NOT EXISTS user_insights (
  user_id UUID PRIMARY KEY,
  version INT NOT NULL DEFAULT 1,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source TEXT NOT NULL DEFAULT 'nightly', -- 'nightly' | 'on_complete' | 'adhoc'
  stale_at TIMESTAMPTZ NULL,
  checksum TEXT NULL,
  facts JSONB NOT NULL DEFAULT '{}'::jsonb,
  triggers JSONB NOT NULL DEFAULT '{}'::jsonb,
  insights JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Enable RLS so users can only read their own insights
ALTER TABLE user_insights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_insights_owner_policy ON user_insights;
CREATE POLICY user_insights_owner_policy ON user_insights
  FOR ALL
  USING (user_id::text = auth.uid()::text)
  WITH CHECK (user_id::text = auth.uid()::text);

-- Helpful index for admin/maintenance
CREATE INDEX IF NOT EXISTS idx_user_insights_generated_at ON user_insights (generated_at DESC);

-- Compute deterministic facts for a user as JSONB using existing tables
-- Assumes tables: user, ruck_session, session_splits, user_achievements, achievements
-- This function focuses on recent aggregates and a small recent splits window
CREATE OR REPLACE FUNCTION compute_user_facts(u_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  prefer_metric BOOLEAN := TRUE;
  now_utc TIMESTAMPTZ := NOW();
  facts JSONB := '{}'::jsonb;
BEGIN
  -- Pull preference and simple profile
  SELECT COALESCE(prefer_metric, TRUE)
    INTO prefer_metric
  FROM "user"
  WHERE id = u_id
  LIMIT 1;

  -- Totals (30/90 days) and recency
  WITH recent AS (
    SELECT * FROM ruck_session
    WHERE user_id = u_id AND status = 'completed'
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
  , all_time AS (
    SELECT COALESCE(SUM(distance_km),0) AS dist_km,
           COALESCE(SUM(elevation_gain_m),0) AS elev_m,
           COUNT(*) AS sessions
    FROM recent
  )
  SELECT jsonb_build_object(
    'prefer_metric', prefer_metric,
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
      'last_ruck_weight_kg', (SELECT ruck_weight_kg FROM last_done)
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
    WHERE user_id = u_id AND status = 'completed'
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
    FROM ruck_session WHERE user_id = u_id AND status='completed'
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

  RETURN facts;
END;
$$;

-- Upsert helper: write snapshot to user_insights
CREATE OR REPLACE FUNCTION upsert_user_insights(u_id UUID, src TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  f JSONB;
  prefer_metric BOOLEAN := TRUE;
  trig JSONB := '{}'::jsonb;
BEGIN
  f := compute_user_facts(u_id);

  -- Build simple triggers (example: next distance milestone)
  SELECT COALESCE(prefer_metric, TRUE) INTO prefer_metric FROM "user" WHERE id = u_id LIMIT 1;
  WITH at AS (
    SELECT COALESCE(SUM(distance_km),0) AS dist_km
    FROM ruck_session WHERE user_id = u_id AND status='completed'
  )
  SELECT jsonb_build_object(
    'next_distance_milestone',
      CASE WHEN prefer_metric THEN CEIL(at.dist_km)
           ELSE CEIL(at.dist_km * 0.621371) END,
    'unit', CASE WHEN prefer_metric THEN 'km' ELSE 'mi' END
  ) INTO trig FROM at;

  INSERT INTO user_insights(user_id, version, generated_at, source, facts, triggers, insights)
  VALUES (u_id, 1, NOW(), COALESCE(src,'nightly'), f, trig, '{}'::jsonb)
  ON CONFLICT (user_id)
  DO UPDATE SET
    version = EXCLUDED.version,
    generated_at = EXCLUDED.generated_at,
    source = EXCLUDED.source,
    facts = EXCLUDED.facts,
    triggers = EXCLUDED.triggers;
END;
$$;


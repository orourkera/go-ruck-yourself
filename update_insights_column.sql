-- Update the upsert_user_insights function to also populate the insights column
-- with commonly accessed fields for easier retrieval

CREATE OR REPLACE FUNCTION upsert_user_insights(u_id UUID, src TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  f JSONB;
  prefer_metric BOOLEAN := TRUE;
  trig JSONB := '{}'::jsonb;
  ins JSONB := '{}'::jsonb;
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

  -- Build insights JSONB with the commonly accessed fields
  -- This makes it easier for the API to retrieve these values
  ins := jsonb_build_object(
    'total_sessions', COALESCE((f->>'total_sessions')::int, 0),
    'total_distance_km', COALESCE((f->>'total_distance_km')::numeric, 0),
    'total_duration_hours', COALESCE((f->>'total_duration_hours')::numeric, 0),
    'avg_pace_per_km_seconds', COALESCE((f->>'avg_pace_per_km_seconds')::numeric, 0),
    'total_elevation_gain_m', COALESCE((f->>'total_elevation_gain_m')::numeric, 0),
    'recent_sessions_count', COALESCE((f->>'recent_sessions_count')::int, 0),
    'recent_avg_distance_km', COALESCE((f->>'recent_avg_distance_km')::numeric, 0),
    'recent_avg_pace_per_km_seconds', COALESCE((f->>'recent_avg_pace_per_km_seconds')::numeric, 0),
    'achievements_total', COALESCE((f->>'achievements_total')::int, 0),
    'achievements_recent', COALESCE((f->>'achievements_recent')::int, 0),
    'current_streak_days', COALESCE((f->>'current_streak_days')::int, 0),
    'longest_streak_days', COALESCE((f->>'longest_streak_days')::int, 0)
  );

  INSERT INTO user_insights(user_id, version, generated_at, source, facts, triggers, insights)
  VALUES (u_id, 1, NOW(), COALESCE(src,'nightly'), f, trig, ins)
  ON CONFLICT (user_id)
  DO UPDATE SET
    version = EXCLUDED.version,
    generated_at = EXCLUDED.generated_at,
    source = EXCLUDED.source,
    facts = EXCLUDED.facts,
    triggers = EXCLUDED.triggers,
    insights = EXCLUDED.insights;
END;
$$;
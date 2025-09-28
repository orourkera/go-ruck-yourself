-- Migration: Create onboarding metrics tracking system
-- Author: Assistant 2025-01-28
-- Purpose: Track user activation, retention, and churn metrics

-- 1. Create the main metrics table
CREATE TABLE IF NOT EXISTS user_onboarding_metrics (
  user_id UUID PRIMARY KEY REFERENCES "user"(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL,

  -- Activation metrics
  first_session_started_at TIMESTAMPTZ,
  first_session_completed_at TIMESTAMPTZ,
  first_session_id BIGINT REFERENCES ruck_session(id),
  time_to_first_ruck_hours FLOAT,

  -- Retention metrics
  second_session_completed_at TIMESTAMPTZ,
  second_session_id BIGINT REFERENCES ruck_session(id),
  time_to_second_ruck_hours FLOAT,

  -- Activity counts by period
  sessions_day_1 INT DEFAULT 0,
  sessions_week_1 INT DEFAULT 0,
  sessions_week_2 INT DEFAULT 0,
  sessions_month_1 INT DEFAULT 0,
  sessions_month_2 INT DEFAULT 0,

  -- Engagement metrics
  has_set_weight BOOLEAN DEFAULT FALSE,
  has_created_coaching_plan BOOLEAN DEFAULT FALSE,
  has_joined_club BOOLEAN DEFAULT FALSE,
  has_added_buddy BOOLEAN DEFAULT FALSE,
  has_health_integration BOOLEAN DEFAULT FALSE,
  has_strava_connected BOOLEAN DEFAULT FALSE,
  profile_completion_score FLOAT DEFAULT 0, -- 0-100

  -- Churn indicators
  last_session_at TIMESTAMPTZ,
  days_since_last_session INT,
  is_churned BOOLEAN DEFAULT FALSE,
  churned_at TIMESTAMPTZ,
  churn_risk_score FLOAT, -- 0-100, higher = more likely to churn

  -- User segments
  user_segment TEXT, -- 'never_started', 'one_and_done', 'activated', 'engaged', 'churned'
  activation_cohort TEXT, -- 'day_1', 'week_1', 'week_2', 'month_1', 'never'

  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX idx_onboarding_metrics_segment ON user_onboarding_metrics(user_segment);
CREATE INDEX idx_onboarding_metrics_churned ON user_onboarding_metrics(is_churned);
CREATE INDEX idx_onboarding_metrics_created ON user_onboarding_metrics(created_at);
CREATE INDEX idx_onboarding_metrics_cohort ON user_onboarding_metrics(activation_cohort);

-- 2. Function to initialize metrics for a new user
CREATE OR REPLACE FUNCTION initialize_user_onboarding_metrics()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_onboarding_metrics (
    user_id,
    created_at,
    has_set_weight,
    has_strava_connected,
    profile_completion_score,
    user_segment
  ) VALUES (
    NEW.id,
    NEW.created_at,
    NEW.weight_kg IS NOT NULL,
    NEW.strava_athlete_id IS NOT NULL,
    CASE
      WHEN NEW.weight_kg IS NOT NULL THEN 20
      ELSE 0
    END +
    CASE
      WHEN NEW.height_cm IS NOT NULL THEN 10
      ELSE 0
    END +
    CASE
      WHEN NEW.avatar_url IS NOT NULL THEN 15
      ELSE 0
    END +
    CASE
      WHEN NEW.date_of_birth IS NOT NULL THEN 10
      ELSE 0
    END +
    CASE
      WHEN NEW.equipment_type IS NOT NULL THEN 10
      ELSE 0
    END,
    'never_started'
  ) ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Function to update metrics when a session is completed
CREATE OR REPLACE FUNCTION update_onboarding_metrics_on_session()
RETURNS TRIGGER AS $$
DECLARE
  user_created_at TIMESTAMPTZ;
  first_completed_at TIMESTAMPTZ;
  session_count_week_1 INT;
  session_count_month_1 INT;
BEGIN
  -- Only process completed sessions
  IF NEW.status != 'completed' THEN
    RETURN NEW;
  END IF;

  -- Get user creation date
  SELECT created_at INTO user_created_at
  FROM "user"
  WHERE id = NEW.user_id;

  -- Get existing first session time
  SELECT first_session_completed_at INTO first_completed_at
  FROM user_onboarding_metrics
  WHERE user_id = NEW.user_id;

  -- Update metrics
  UPDATE user_onboarding_metrics
  SET
    -- First session tracking
    first_session_started_at = COALESCE(first_session_started_at, NEW.started_at),
    first_session_completed_at = COALESCE(first_session_completed_at, NEW.completed_at),
    first_session_id = COALESCE(first_session_id, NEW.id),
    time_to_first_ruck_hours = CASE
      WHEN first_session_completed_at IS NULL
      THEN EXTRACT(EPOCH FROM (NEW.completed_at - user_created_at)) / 3600
      ELSE time_to_first_ruck_hours
    END,

    -- Second session tracking
    second_session_completed_at = CASE
      WHEN first_completed_at IS NOT NULL AND first_completed_at < NEW.completed_at AND second_session_completed_at IS NULL
      THEN NEW.completed_at
      ELSE second_session_completed_at
    END,
    second_session_id = CASE
      WHEN first_completed_at IS NOT NULL AND first_completed_at < NEW.completed_at AND second_session_id IS NULL
      THEN NEW.id
      ELSE second_session_id
    END,
    time_to_second_ruck_hours = CASE
      WHEN first_completed_at IS NOT NULL AND first_completed_at < NEW.completed_at AND second_session_completed_at IS NULL
      THEN EXTRACT(EPOCH FROM (NEW.completed_at - first_completed_at)) / 3600
      ELSE time_to_second_ruck_hours
    END,

    -- Activity counts
    sessions_day_1 = CASE
      WHEN NEW.completed_at <= user_created_at + INTERVAL '1 day'
      THEN sessions_day_1 + 1
      ELSE sessions_day_1
    END,
    sessions_week_1 = CASE
      WHEN NEW.completed_at <= user_created_at + INTERVAL '7 days'
      THEN sessions_week_1 + 1
      ELSE sessions_week_1
    END,
    sessions_week_2 = CASE
      WHEN NEW.completed_at > user_created_at + INTERVAL '7 days'
       AND NEW.completed_at <= user_created_at + INTERVAL '14 days'
      THEN sessions_week_2 + 1
      ELSE sessions_week_2
    END,
    sessions_month_1 = CASE
      WHEN NEW.completed_at <= user_created_at + INTERVAL '30 days'
      THEN sessions_month_1 + 1
      ELSE sessions_month_1
    END,

    -- Update segment and cohort
    user_segment = CASE
      WHEN second_session_completed_at IS NOT NULL OR
           (first_completed_at IS NOT NULL AND first_completed_at < NEW.completed_at)
      THEN 'activated'
      WHEN first_session_completed_at IS NULL
      THEN 'activated' -- First session just completed
      ELSE user_segment
    END,

    activation_cohort = CASE
      WHEN first_session_completed_at IS NULL THEN
        CASE
          WHEN NEW.completed_at <= user_created_at + INTERVAL '1 day' THEN 'day_1'
          WHEN NEW.completed_at <= user_created_at + INTERVAL '7 days' THEN 'week_1'
          WHEN NEW.completed_at <= user_created_at + INTERVAL '14 days' THEN 'week_2'
          WHEN NEW.completed_at <= user_created_at + INTERVAL '30 days' THEN 'month_1'
          ELSE 'month_plus'
        END
      ELSE activation_cohort
    END,

    -- Update last session tracking
    last_session_at = NEW.completed_at,
    days_since_last_session = 0,
    is_churned = FALSE,
    churned_at = NULL,

    updated_at = NOW()
  WHERE user_id = NEW.user_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Daily job to update churn metrics and segments
CREATE OR REPLACE FUNCTION update_churn_metrics()
RETURNS VOID AS $$
BEGIN
  UPDATE user_onboarding_metrics
  SET
    days_since_last_session = EXTRACT(DAY FROM (NOW() - last_session_at)),

    -- Mark as churned if no activity in 30 days
    is_churned = CASE
      WHEN last_session_at IS NOT NULL AND last_session_at < NOW() - INTERVAL '30 days'
      THEN TRUE
      ELSE FALSE
    END,

    churned_at = CASE
      WHEN is_churned = FALSE AND last_session_at < NOW() - INTERVAL '30 days'
      THEN NOW()
      ELSE churned_at
    END,

    -- Update segments based on current state
    user_segment = CASE
      -- Never started a session
      WHEN first_session_completed_at IS NULL AND created_at < NOW() - INTERVAL '30 days'
      THEN 'never_started'

      -- One and done (only 1 session, more than 14 days ago)
      WHEN first_session_completed_at IS NOT NULL
       AND second_session_completed_at IS NULL
       AND first_session_completed_at < NOW() - INTERVAL '14 days'
      THEN 'one_and_done'

      -- Churned (was active but stopped)
      WHEN last_session_at < NOW() - INTERVAL '30 days'
      THEN 'churned'

      -- Engaged (multiple sessions in recent period)
      WHEN sessions_month_1 >= 4 OR
           (second_session_completed_at IS NOT NULL AND last_session_at > NOW() - INTERVAL '7 days')
      THEN 'engaged'

      -- Keep existing
      ELSE user_segment
    END,

    -- Calculate churn risk score (0-100)
    churn_risk_score = CASE
      WHEN last_session_at IS NULL THEN 90
      WHEN days_since_last_session >= 21 THEN 80
      WHEN days_since_last_session >= 14 THEN 60
      WHEN days_since_last_session >= 7 THEN 40
      WHEN sessions_month_1 >= 8 THEN 10
      WHEN sessions_month_1 >= 4 THEN 20
      ELSE 30
    END,

    updated_at = NOW()
  WHERE last_session_at IS NOT NULL OR created_at > NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql;

-- 5. Create triggers
DROP TRIGGER IF EXISTS trigger_initialize_onboarding_metrics ON "user";
CREATE TRIGGER trigger_initialize_onboarding_metrics
  AFTER INSERT ON "user"
  FOR EACH ROW
  EXECUTE FUNCTION initialize_user_onboarding_metrics();

DROP TRIGGER IF EXISTS trigger_update_onboarding_metrics ON ruck_session;
CREATE TRIGGER trigger_update_onboarding_metrics
  AFTER INSERT OR UPDATE OF status ON ruck_session
  FOR EACH ROW
  EXECUTE FUNCTION update_onboarding_metrics_on_session();

-- 6. Initialize metrics for existing users
INSERT INTO user_onboarding_metrics (
  user_id,
  created_at,
  has_set_weight,
  has_strava_connected,
  user_segment
)
SELECT
  u.id,
  u.created_at,
  u.weight_kg IS NOT NULL,
  u.strava_athlete_id IS NOT NULL,
  CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM ruck_session rs
      WHERE rs.user_id = u.id AND rs.status = 'completed'
    ) THEN 'never_started'
    ELSE 'activated'
  END
FROM "user" u
WHERE NOT EXISTS (
  SELECT 1 FROM user_onboarding_metrics uom WHERE uom.user_id = u.id
);

-- 7. Backfill session data for existing users
WITH first_sessions AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    id as session_id,
    started_at,
    completed_at
  FROM ruck_session
  WHERE status = 'completed'
  ORDER BY user_id, completed_at ASC
),
second_sessions AS (
  SELECT DISTINCT ON (rs.user_id)
    rs.user_id,
    rs.id as session_id,
    rs.completed_at
  FROM ruck_session rs
  JOIN first_sessions fs ON rs.user_id = fs.user_id
  WHERE rs.status = 'completed'
    AND rs.completed_at > fs.completed_at
  ORDER BY rs.user_id, rs.completed_at ASC
),
session_counts AS (
  SELECT
    rs.user_id,
    u.created_at as user_created,
    COUNT(CASE WHEN rs.completed_at <= u.created_at + INTERVAL '1 day' THEN 1 END) as day_1,
    COUNT(CASE WHEN rs.completed_at <= u.created_at + INTERVAL '7 days' THEN 1 END) as week_1,
    COUNT(CASE WHEN rs.completed_at > u.created_at + INTERVAL '7 days'
               AND rs.completed_at <= u.created_at + INTERVAL '14 days' THEN 1 END) as week_2,
    COUNT(CASE WHEN rs.completed_at <= u.created_at + INTERVAL '30 days' THEN 1 END) as month_1,
    MAX(rs.completed_at) as last_session
  FROM ruck_session rs
  JOIN "user" u ON rs.user_id = u.id
  WHERE rs.status = 'completed'
  GROUP BY rs.user_id, u.created_at
)
UPDATE user_onboarding_metrics uom
SET
  first_session_started_at = fs.started_at,
  first_session_completed_at = fs.completed_at,
  first_session_id = fs.session_id,
  time_to_first_ruck_hours = EXTRACT(EPOCH FROM (fs.completed_at - u.created_at)) / 3600,
  second_session_completed_at = ss.completed_at,
  second_session_id = ss.session_id,
  time_to_second_ruck_hours = EXTRACT(EPOCH FROM (ss.completed_at - fs.completed_at)) / 3600,
  sessions_day_1 = COALESCE(sc.day_1, 0),
  sessions_week_1 = COALESCE(sc.week_1, 0),
  sessions_week_2 = COALESCE(sc.week_2, 0),
  sessions_month_1 = COALESCE(sc.month_1, 0),
  last_session_at = sc.last_session,
  days_since_last_session = EXTRACT(DAY FROM (NOW() - sc.last_session)),
  updated_at = NOW()
FROM "user" u
LEFT JOIN first_sessions fs ON fs.user_id = u.id
LEFT JOIN second_sessions ss ON ss.user_id = u.id
LEFT JOIN session_counts sc ON sc.user_id = u.id
WHERE uom.user_id = u.id;

-- Run initial churn calculation
SELECT update_churn_metrics();

-- 8. Create useful views for analytics

-- View for activation funnel
CREATE OR REPLACE VIEW activation_funnel AS
SELECT
  DATE_TRUNC('week', created_at) as cohort_week,
  COUNT(*) as total_users,
  COUNT(CASE WHEN first_session_completed_at IS NOT NULL THEN 1 END) as activated_users,
  COUNT(CASE WHEN second_session_completed_at IS NOT NULL THEN 1 END) as retained_users,
  COUNT(CASE WHEN user_segment = 'never_started' THEN 1 END) as never_started,
  COUNT(CASE WHEN user_segment = 'one_and_done' THEN 1 END) as one_and_done,
  COUNT(CASE WHEN user_segment = 'engaged' THEN 1 END) as engaged,
  COUNT(CASE WHEN is_churned THEN 1 END) as churned,
  ROUND(100.0 * COUNT(CASE WHEN first_session_completed_at IS NOT NULL THEN 1 END) / NULLIF(COUNT(*), 0), 1) as activation_rate,
  ROUND(100.0 * COUNT(CASE WHEN second_session_completed_at IS NOT NULL THEN 1 END) / NULLIF(COUNT(*), 0), 1) as retention_rate
FROM user_onboarding_metrics
GROUP BY cohort_week
ORDER BY cohort_week DESC;

-- View for time-to-activation analysis
CREATE OR REPLACE VIEW time_to_activation AS
SELECT
  activation_cohort,
  COUNT(*) as user_count,
  ROUND(AVG(time_to_first_ruck_hours), 1) as avg_hours_to_first_ruck,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY time_to_first_ruck_hours), 1) as median_hours_to_first_ruck,
  ROUND(AVG(time_to_second_ruck_hours), 1) as avg_hours_to_second_ruck,
  ROUND(AVG(sessions_week_1), 1) as avg_sessions_week_1,
  ROUND(AVG(sessions_month_1), 1) as avg_sessions_month_1
FROM user_onboarding_metrics
WHERE first_session_completed_at IS NOT NULL
GROUP BY activation_cohort
ORDER BY
  CASE activation_cohort
    WHEN 'day_1' THEN 1
    WHEN 'week_1' THEN 2
    WHEN 'week_2' THEN 3
    WHEN 'month_1' THEN 4
    WHEN 'month_plus' THEN 5
    ELSE 6
  END;

-- View for churn risk analysis
CREATE OR REPLACE VIEW churn_risk_analysis AS
SELECT
  CASE
    WHEN churn_risk_score >= 80 THEN 'Critical'
    WHEN churn_risk_score >= 60 THEN 'High'
    WHEN churn_risk_score >= 40 THEN 'Medium'
    WHEN churn_risk_score >= 20 THEN 'Low'
    ELSE 'Very Low'
  END as risk_level,
  COUNT(*) as user_count,
  ROUND(AVG(days_since_last_session), 1) as avg_days_inactive,
  ROUND(AVG(sessions_month_1), 1) as avg_sessions_first_month,
  COUNT(CASE WHEN has_created_coaching_plan THEN 1 END) as with_coaching_plan,
  COUNT(CASE WHEN has_strava_connected THEN 1 END) as with_strava
FROM user_onboarding_metrics
WHERE NOT is_churned AND first_session_completed_at IS NOT NULL
GROUP BY risk_level
ORDER BY
  CASE risk_level
    WHEN 'Critical' THEN 1
    WHEN 'High' THEN 2
    WHEN 'Medium' THEN 3
    WHEN 'Low' THEN 4
    ELSE 5
  END;

-- Grant appropriate permissions
GRANT SELECT ON user_onboarding_metrics TO authenticated;
GRANT SELECT ON activation_funnel TO authenticated;
GRANT SELECT ON time_to_activation TO authenticated;
GRANT SELECT ON churn_risk_analysis TO authenticated;
-- Add timezone support to coaching plans
ALTER TABLE user_coaching_plans
ADD COLUMN IF NOT EXISTS plan_notification_timezone VARCHAR(50) DEFAULT 'UTC';

-- Add index for notification queries
CREATE INDEX IF NOT EXISTS idx_user_coaching_plans_timezone
ON user_coaching_plans(plan_notification_timezone);

-- Update existing active plans to UTC (safe default)
UPDATE user_coaching_plans
SET plan_notification_timezone = 'UTC'
WHERE plan_notification_timezone IS NULL;

-- Add comment
COMMENT ON COLUMN user_coaching_plans.plan_notification_timezone IS 'IANA timezone identifier for scheduling notifications (e.g., America/New_York)';
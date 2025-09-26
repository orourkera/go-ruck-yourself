-- Add CASCADE DELETE to plan_sessions foreign key
-- When a user_coaching_plan is deleted, all its sessions should be deleted too

ALTER TABLE plan_sessions
DROP CONSTRAINT IF EXISTS plan_sessions_user_coaching_plan_id_fkey;

ALTER TABLE plan_sessions
ADD CONSTRAINT plan_sessions_user_coaching_plan_id_fkey
FOREIGN KEY (user_coaching_plan_id)
REFERENCES user_coaching_plans(id)
ON DELETE CASCADE;
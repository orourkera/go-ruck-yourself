-- Add review fields to user_coaching_plans and create plan_review_audit table

-- 1) user_coaching_plans review columns
ALTER TABLE user_coaching_plans
  ADD COLUMN IF NOT EXISTS review_status VARCHAR(50) DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS review_summary JSONB;

-- Optional constraint for status values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_review_status'
  ) THEN
    ALTER TABLE user_coaching_plans
      ADD CONSTRAINT valid_review_status CHECK (review_status IN ('pending','approved','corrected','failed'));
  END IF;
END $$;

-- 2) plan_review_audit table for detailed logs
CREATE TABLE IF NOT EXISTS plan_review_audit (
  id SERIAL PRIMARY KEY,
  user_coaching_plan_id INTEGER REFERENCES user_coaching_plans(id) ON DELETE CASCADE,
  reviewer VARCHAR(50) DEFAULT 'ai',
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  issues JSONB,
  corrections JSONB,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_plan_review_audit_plan ON plan_review_audit(user_coaching_plan_id);
CREATE INDEX IF NOT EXISTS idx_user_coaching_plans_review_status ON user_coaching_plans(review_status);

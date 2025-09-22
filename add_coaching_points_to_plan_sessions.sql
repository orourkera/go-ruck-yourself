-- Migration: Add coaching_points column to plan_sessions table
-- This column stores specific coaching points for each session that the AI cheerleader can use
-- to provide real-time prompts during workouts

-- Add coaching_points column to plan_sessions table
ALTER TABLE plan_sessions
ADD COLUMN IF NOT EXISTS coaching_points JSONB DEFAULT '{}';

-- The coaching_points column will store structured data like:
-- {
--   "intervals": [
--     {"type": "warmup", "duration_minutes": 5, "instruction": "Easy pace to warm up"},
--     {"type": "work", "duration_minutes": 2, "instruction": "Push hard! Increase your pace"},
--     {"type": "recovery", "duration_minutes": 2, "instruction": "Slow down and recover"},
--     {"type": "work", "duration_minutes": 2, "instruction": "Back to fast pace!"},
--     {"type": "recovery", "duration_minutes": 2, "instruction": "Easy recovery pace"},
--     {"type": "cooldown", "duration_minutes": 5, "instruction": "Cool down with easy walking"}
--   ],
--   "milestones": [
--     {"distance_km": 1, "message": "Great job on your first kilometer!"},
--     {"distance_km": 2.5, "message": "Halfway there! Keep pushing!"},
--     {"distance_km": 5, "message": "Fantastic! You've completed 5km!"}
--   ],
--   "time_triggers": [
--     {"elapsed_minutes": 10, "message": "10 minutes in - you're doing great!"},
--     {"elapsed_minutes": 20, "message": "20 minutes strong! Maintain your form"},
--     {"elapsed_minutes": 30, "message": "30 minutes! You're crushing this workout!"}
--   ],
--   "heart_rate_zones": [
--     {"zone": 2, "min_bpm": 120, "max_bpm": 140, "instruction": "Stay in Zone 2 for aerobic base"},
--     {"zone": 3, "min_bpm": 141, "max_bpm": 160, "instruction": "Zone 3 - comfortably hard pace"},
--     {"zone": 4, "min_bpm": 161, "max_bpm": 180, "instruction": "Zone 4 - high intensity effort"}
--   ],
--   "session_goals": {
--     "primary": "Complete 2-minute high-intensity intervals",
--     "secondary": "Maintain consistent pace during recovery periods",
--     "focus_points": ["breathing rhythm", "posture", "cadence"]
--   }
-- }

-- Add index for performance when querying sessions with coaching points
CREATE INDEX IF NOT EXISTS idx_plan_sessions_coaching_points
ON plan_sessions USING GIN (coaching_points);

-- Add comment to document the column
COMMENT ON COLUMN plan_sessions.coaching_points IS
'Stores structured coaching instructions for AI cheerleader including intervals, milestones, time triggers, and heart rate zones';
-- Add custom_questions column to coaching_plan_templates table
ALTER TABLE coaching_plan_templates
ADD COLUMN IF NOT EXISTS custom_questions JSONB;

-- Update existing templates with custom questions for each plan type
UPDATE coaching_plan_templates
SET custom_questions =
CASE
  -- Load Capacity Builder
  WHEN plan_id = 'load-capacity' THEN
    '[
      {
        "id": "target_load",
        "prompt": "What load are you working up to?",
        "type": "slider",
        "min": 10,
        "max": 60,
        "step": 5,
        "unit": "kg",
        "default": 20,
        "maps_to": "targetLoadKg",
        "helper_text": "Your goal weight to carry comfortably for 60+ minutes"
      },
      {
        "id": "current_max_load",
        "prompt": "What''s the heaviest you''ve rucked with recently?",
        "type": "number",
        "unit": "kg",
        "maps_to": "currentMaxLoadKg",
        "validation": {
          "min": 0,
          "max": 100
        },
        "helper_text": "Be honest - we''ll build from here safely"
      },
      {
        "id": "injury_concerns",
        "prompt": "Any areas we should be careful with?",
        "type": "chips",
        "options": ["Back", "Knees", "Ankles", "Shoulders", "None"],
        "multiple": true,
        "maps_to": "injuryConcerns"
      }
    ]'::jsonb

  -- Daily Discipline Streak
  WHEN plan_id = 'daily-discipline' THEN
    '[
      {
        "id": "streak_goal",
        "prompt": "How many consecutive days are you targeting?",
        "type": "chips",
        "options": [
          {"label": "7 days", "value": 7},
          {"label": "14 days", "value": 14},
          {"label": "21 days", "value": 21},
          {"label": "30 days", "value": 30},
          {"label": "Custom", "value": "custom"}
        ],
        "maps_to": "streakTargetDays",
        "required": true
      },
      {
        "id": "custom_streak_days",
        "prompt": "Enter your custom streak target (days):",
        "type": "number",
        "show_condition": {"field": "streak_goal", "equals": "custom"},
        "maps_to": "streakTargetDays",
        "validation": {
          "min": 3,
          "max": 100
        }
      },
      {
        "id": "minimum_time",
        "prompt": "Minimum session length on tough days?",
        "type": "slider",
        "min": 10,
        "max": 45,
        "step": 5,
        "unit": "minutes",
        "default": 20,
        "maps_to": "minimumSessionMinutes",
        "helper_text": "Your non-negotiable minimum to keep the streak alive"
      }
    ]'::jsonb

  -- Fat Loss & Feel Better
  WHEN plan_id = 'fat-loss' THEN
    '[
      {
        "id": "weight_loss_target",
        "prompt": "Weight loss goal over 12 weeks?",
        "type": "slider",
        "min": 2,
        "max": 15,
        "step": 0.5,
        "unit": "kg",
        "default": 5,
        "maps_to": "weightLossTargetKg",
        "helper_text": "0.5-1kg/week is sustainable"
      },
      {
        "id": "current_activity",
        "prompt": "Current weekly activity level?",
        "type": "chips",
        "options": [
          {"label": "Sedentary", "value": "sedentary"},
          {"label": "Light (1-2x/week)", "value": "light"},
          {"label": "Moderate (3-4x/week)", "value": "moderate"},
          {"label": "Active (5+x/week)", "value": "active"}
        ],
        "maps_to": "currentActivityLevel",
        "required": true
      },
      {
        "id": "complementary_activities",
        "prompt": "What else will you do alongside rucking?",
        "type": "chips",
        "options": ["Strength training", "Running", "Cycling", "Swimming", "Yoga", "None"],
        "multiple": true,
        "maps_to": "complementaryActivities"
      }
    ]'::jsonb

  -- Get Faster at Rucking
  WHEN plan_id = 'get-faster' THEN
    '[
      {
        "id": "current_pace",
        "prompt": "Current 60-minute ruck pace (min/km)?",
        "type": "number",
        "maps_to": "currentPaceMinPerKm",
        "validation": {
          "min": 6,
          "max": 12
        },
        "helper_text": "Your comfortable pace for 60 minutes with standard load"
      },
      {
        "id": "target_pace",
        "prompt": "Goal 60-minute pace (min/km)?",
        "type": "number",
        "maps_to": "targetPaceMinPerKm",
        "validation": {
          "min": 5,
          "max": 10
        },
        "helper_text": "Be realistic - 30sec/km improvement is significant"
      },
      {
        "id": "speed_work_experience",
        "prompt": "Experience with speed/interval training?",
        "type": "chips",
        "options": [
          {"label": "None", "value": "none"},
          {"label": "Some", "value": "some"},
          {"label": "Extensive", "value": "extensive"}
        ],
        "maps_to": "speedWorkExperience",
        "required": true
      }
    ]'::jsonb

  -- Event Prep
  WHEN plan_id = 'event-prep' THEN
    '[
      {
        "id": "event_date",
        "prompt": "When is your event?",
        "type": "date",
        "maps_to": "eventDate",
        "validation": {
          "min_days_from_now": 14,
          "max_days_from_now": 365
        },
        "required": true,
        "helper_text": "We''ll build your taper timing around this"
      },
      {
        "id": "event_distance",
        "prompt": "Event distance (km)?",
        "type": "number",
        "default": 19.3,
        "maps_to": "eventDistanceKm",
        "validation": {
          "min": 5,
          "max": 50
        },
        "helper_text": "12 miles = 19.3km"
      },
      {
        "id": "event_load",
        "prompt": "Required event load (kg)?",
        "type": "number",
        "maps_to": "eventLoadKg",
        "validation": {
          "min": 5,
          "max": 50
        },
        "helper_text": "The weight you''ll carry during the event"
      },
      {
        "id": "time_goal",
        "prompt": "Target finish time?",
        "type": "text",
        "maps_to": "targetFinishTime",
        "placeholder": "e.g., 2:45:00 or sub-3 hours",
        "helper_text": "Optional but helps set training paces"
      }
    ]'::jsonb

  -- Age Strong & Posture/Balance
  WHEN plan_id = 'age-strong' THEN
    '[
      {
        "id": "primary_goals",
        "prompt": "What matters most to you?",
        "type": "chips",
        "options": [
          "Better posture",
          "Improved balance",
          "Joint health",
          "Daily energy",
          "Confidence walking"
        ],
        "multiple": true,
        "maps_to": "primaryGoals",
        "required": true
      },
      {
        "id": "mobility_concerns",
        "prompt": "Any mobility limitations?",
        "type": "chips",
        "options": [
          "Stairs difficult",
          "Balance issues",
          "Joint stiffness",
          "Previous falls",
          "None"
        ],
        "multiple": true,
        "maps_to": "mobilityConcerns"
      },
      {
        "id": "preferred_terrain",
        "prompt": "Preferred walking surface?",
        "type": "chips",
        "options": [
          {"label": "Flat paths", "value": "flat"},
          {"label": "Some hills OK", "value": "moderate"},
          {"label": "Varied terrain", "value": "varied"}
        ],
        "maps_to": "preferredTerrain",
        "required": true
      }
    ]'::jsonb

  ELSE NULL
END
WHERE plan_id IN ('load-capacity', 'daily-discipline', 'fat-loss', 'get-faster', 'event-prep', 'age-strong');

-- Add comment explaining the structure
COMMENT ON COLUMN coaching_plan_templates.custom_questions IS 'Plan-specific questions array with type (slider/chips/text/number/date), validation rules, and mapping to personalization fields';
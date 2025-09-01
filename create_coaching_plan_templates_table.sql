-- Create coaching plan templates table
CREATE TABLE coaching_plan_templates (
    id SERIAL PRIMARY KEY,
    plan_id VARCHAR(50) NOT NULL UNIQUE, -- fat-loss, get-faster, etc.
    name VARCHAR(100) NOT NULL,
    duration_weeks INTEGER NOT NULL,
    base_structure JSONB NOT NULL, -- Sessions per week, intensity zones, etc.
    progression_rules JSONB NOT NULL, -- How to advance weekly
    non_negotiables JSONB NOT NULL, -- Safety/recovery rules
    retests JSONB NOT NULL, -- When to measure progress
    personalization_knobs JSONB NOT NULL, -- What can be customized
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for fast lookups
CREATE INDEX idx_coaching_plan_templates_plan_id ON coaching_plan_templates(plan_id);
CREATE INDEX idx_coaching_plan_templates_active ON coaching_plan_templates(is_active);

-- Insert existing science-based plans from the codebase
INSERT INTO coaching_plan_templates (plan_id, name, duration_weeks, base_structure, progression_rules, non_negotiables, retests, personalization_knobs) VALUES 

-- Fat Loss & Feel Better
('fat-loss', 'Fat Loss & Feel Better', 12, 
'{"sessions_per_week": {"rucks": 3, "unloaded_cardio": 2, "strength": 2}, "strength_duration": "30-35 min", "starting_load": {"percentage": "10-15% bodyweight", "cap": "18 kg / 40 lb"}, "weekly_ruck_minutes": {"start": "120-150", "end": "170-200"}, "intensity": {"z2": "40-59% HRR (RPE 3-4)"}}',
'{"one_knob_per_week": true, "options": ["+5-10 min to one ruck", "+50-100 m vert on one ruck", "+1-2% BW every 2-3 weeks if recovery green"], "deload": {"frequency": "every 4th week", "reduction": "≈-30% ruck minutes"}}',
'{"ruck_frequency_cap": "≤4/week", "repeat_week_if": ["HR drift is high", "RPE >5", "next-day joints are not normal"]}',
'{"body_mass": "weekly", "30min_ruck_tt": "weeks 0/6/12"}',
'{"time_budget": true, "scheduled_days": true, "equipment": true, "safe_starting_load": true, "terrain_access": true, "intensity_control": true, "risk_profile": true, "route_weather_swaps": true}'),

-- Get Faster at Rucking
('get-faster', 'Get Faster at Rucking', 8,
'{"sessions_per_week": {"rucks": 3, "unloaded_cardio": 1}, "ruck_types": {"A_Z2_duration": "45→70 min", "B_tempo": "20-35 min \"comfortably hard\" in 40-55 min session", "C_hills_z2": "40-60 min; +50-100 m vert/week if green"}, "starting_load": {"percentage": "10-15% BW", "hold_until": "≥week 3"}, "intensity": {"z2": "40-59% HRR / RPE 3-4", "tempo": "≈60-70% HRR / RPE 6-7"}}',
'{"one_variable_at_a_time": true, "deload": {"week": 4, "reduction": "≈-30% time/vert"}, "no_load_bumps_on_tempo_hills_during_deload": true}',
'{"progress_one_variable_at_a_time": true, "no_load_bumps_on_tempo_hills_during_deload": true}',
'{"60min_ruck": "week 8 at baseline load/route"}',
'{"time_budget": true, "scheduled_days": true, "equipment": true, "safe_starting_load": true, "terrain_access": true, "intensity_control": true, "risk_profile": true, "route_weather_swaps": true}'),

-- Event Prep (12-mile under 3:00)
('event-prep', '12-mile under 3:00 (or custom event)', 12,
'{"sessions_per_week": {"rucks": 3, "easy_run_bike": 1}, "run_bike_duration": "30-45 min", "ruck_types": {"intervals": "6-10 × 2:00 hard / 2:00 easy (fixed load)", "tempo": "40-55 min with 2×10-12 min surges @ RPE 6-7 (fixed load)", "long_ruck": "build 90 → 150-165 min; practice fueling every 30-40 min"}, "target_load_range": "≈14-20 kg (30-45 lb), personalized"}',
'{"load_rule": "Only Long day may add +2 kg every 2-3 weeks if recovery green", "fixed_load_for_intervals_tempo": true, "vert": "+100-150 m/wk on Tempo or Long as tolerated", "deload": {"frequency": "every 4th week", "reduction": "≈-30% volume"}, "key_milestone": "10-mile simulation ≈2 weeks before event"}',
'{"rest_between_hard_rucks": "≥48 h", "no_new_load_prs_in_taper": true}',
'{"ten_mile_simulation": "≈2 weeks before event"}',
'{"time_budget": true, "scheduled_days": true, "equipment": true, "safe_starting_load": true, "terrain_access": true, "intensity_control": true, "risk_profile": true, "route_weather_swaps": true, "event_specifics": true}'),

-- Daily Discipline Streak
('daily-discipline', 'Daily Discipline Streak', 4,
'{"primary_aim": "daily movement without overuse", "weekly_structure": {"light_vest_recovery_walks": "2-3 × 10-20 min @ 5-10% BW", "unloaded_z2": "2 × 30-45 min", "unloaded_long": "1 × 60-75 min", "optional_strength": "30 min"}, "streak_saver": "user-set \"minimum viable session\" (e.g., 10-15 min unloaded)"}',
'{"soreness": "any soreness/hotspots → drop one vest day; substitute unloaded cardio", "graduation": "30 consecutive days + ≥200 Z2 min/wk, feeling fresh"}',
'{"daily_movement": true, "avoid_overuse": true, "minimum_viable_session": "counts on tough days"}',
'{"streak_tracking": "daily", "weekly_z2_minutes": "weekly target ≥200 min"}',
'{"time_budget": true, "scheduled_days": true, "equipment": true, "safe_starting_load": true, "terrain_access": true, "intensity_control": true, "risk_profile": true, "route_weather_swaps": true, "minimum_viable_session": true}'),

-- Age Strong
('age-strong', 'Posture/Balance & Age Strong', 8,
'{"sessions_per_week": {"light_rucks": "2-3 × 30-50 min @ 6-12% BW", "strength_balance": "2 × step-ups, sit-to-stand, suitcase carries, side planks", "mobility": "10 min"}}',
'{"carries": "+5-10 m/week or add light DBs", "side_plank": "+10-15 s/week", "deload": {"week": 4, "reduction": "reduce one set and ≈20-30% ruck minutes"}}',
'{"prioritize_posture": true, "foot_comfort": true, "impact_progressions": "only if appropriate"}',
'{"balance": "every 2 weeks", "full_retest": "week 8 (plank total, single-leg balance, 10-rep sit-to-stand time)"}',
'{"time_budget": true, "scheduled_days": true, "equipment": true, "safe_starting_load": true, "terrain_access": true, "intensity_control": true, "risk_profile": true, "route_weather_swaps": true}'),

-- Load Capacity Builder
('load-capacity', 'Load Capacity Builder', 8,
'{"who_why": "time-capped users or load-specific goals; build carrying capacity safely", "sessions_per_week": {"rucks": "2-3", "unloaded_cardio": "1-2", "short_strength": "2 × 30-35 min (include suitcase carries)"}, "ruck_types": {"A_Z2_duration": "45-65 min", "B_long_day": "60-120 min (fuel >90 min)", "C_technique_hills": "40-50 min easy with 100-200 m vert (optional)"}, "starting_load": {"percentage": "≈10-12% BW", "cap": "most rec users cap near ≈20% BW for months"}}',
'{"load_rule": "Only Long day progresses load (+1-2% BW every 2-3 weeks if green). Other days hold.", "deload": {"week": 4, "reduction": "≈-30% time; keep load"}}',
'{"weekly_increase_limit": "≤10% weekly increase in total ruck minutes", "ruck_frequency_cap": "≤3/week", "no_ruck_running": true}',
'{"60min_ruck": "week 8 at current Long-day load; compare pace/HR/RPE vs week 1"}',
'{"time_budget": true, "scheduled_days": true, "equipment": true, "safe_starting_load": true, "terrain_access": true, "intensity_control": true, "risk_profile": true, "route_weather_swaps": true}');

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_coaching_plan_templates_modtime
    BEFORE UPDATE ON coaching_plan_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_column();

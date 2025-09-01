-- Update existing coaching plan templates with expert tips data only
-- (Column already exists, just need to populate it)

UPDATE coaching_plan_templates 
SET expert_tips = '{
  "recovery": ["Listen to your body - soreness/joint issues mean repeat the week", "Deload weeks are mandatory for adaptation", "Sleep and nutrition are as important as training"], 
  "progression": ["Only progress one variable per week (time OR load OR elevation)", "Green recovery = normal joints, RPE ≤4, no excessive fatigue"], 
  "mindset": ["Consistency beats intensity", "Build the habit first, performance follows"]
}'
WHERE plan_id = 'fat-loss';

UPDATE coaching_plan_templates 
SET expert_tips = '{
  "training_focus": ["Strength + cardio combo is key for fast rucking", "Elite runners need strength training to become elite ruckers", "Strong people need more cardio volume for speed gains"], 
  "pacing": ["Always aim for negative splits (second half faster)", "Start conservatively, finish strong", "Save energy for the back half"], 
  "specificity": ["Less ruck running = better results until 3 months out", "Focus on running and strength training for base building", "1x/week ruck running maximum when event-specific"]
}'
WHERE plan_id = 'get-faster';

UPDATE coaching_plan_templates 
SET expert_tips = '{
  "timeline": ["Minimum 6 weeks prep for respectable time", "12+ weeks needed to go from unfit to sub-2hr", "Last 7-10 days should be taper (reduce volume, maintain fitness)", "Never cram - adaptations take weeks not days"], 
  "pacing_strategy": ["ALWAYS negative split - second 6 miles faster than first", "Sub-2hr target: ~9:30/mile average with negative split", "Start conservatively around 10:00/mile, finish around 9:00/mile", "Going out too fast destroys back-half performance"], 
  "hydration_fueling": ["Start hydration protocol 3-5 days before event", "Plain water is not enough - need electrolytes", "Practice fueling every 30-40min during long rucks", "High-carb breakfast 2+ hours before (not enough alone)", "Heat acclimatization must start weeks in advance"], 
  "performance_benchmarks": ["Sub-2hr = top 10% territory", "1H55M-2H05M = top 5 finisher range", "2H20M-2H35M = above average", "2H35M-2H45M = average", "Anything under 2H45M puts you ahead of most"], 
  "training_philosophy": ["Aerobic endurance + muscular endurance + full body strength", "Minimize ruck running volume until final months", "Running fitness + strength = ruck speed", "Overtraining is more common than undertraining"]
}'
WHERE plan_id = 'event-prep';

UPDATE coaching_plan_templates 
SET expert_tips = '{
  "streak_psychology": ["Minimum viable session still counts on tough days", "Perfect is the enemy of good - show up consistently", "Missing one day breaks streak, but don''t let it break momentum"], 
  "recovery_focus": ["This plan prioritizes recovery and tissue health", "Light load prevents overuse while building habit", "Any soreness = immediate plan adjustment"], 
  "habit_formation": ["Daily movement creates neural pathways for long-term success", "Start ridiculously small to ensure early wins", "30 days builds automatic behavior patterns"]
}'
WHERE plan_id = 'daily-discipline';

UPDATE coaching_plan_templates 
SET expert_tips = '{
  "longevity_focus": ["Light loads prevent joint wear while building strength", "Functional movements translate to daily life", "Balance training prevents falls and injuries"], 
  "progression_mindset": ["Small consistent gains compound over time", "Quality movement patterns over quantity", "Listen to your body - pain is not gain at this stage"], 
  "foundation_building": ["Master bodyweight before adding load", "Stability before mobility, mobility before strength", "Posture improvements take 6-8 weeks to feel natural"]
}'
WHERE plan_id = 'age-strong';

UPDATE coaching_plan_templates 
SET expert_tips = '{
  "load_progression": ["Only progress load on your longest ruck day", "Hold load constant on shorter sessions", "20% bodyweight is practical ceiling for most people", "Load progression requires excellent recovery"], 
  "tissue_tolerance": ["Gradually build carrying capacity over months not weeks", "Suitcase carries build anti-lateral strength for rucking", "Step-ups prepare legs for load-bearing demands"], 
  "capacity_building": ["Time under load matters more than speed", "Focus on posture and gait efficiency under load", "Fuel sessions over 90 minutes to practice race nutrition"]
}'
WHERE plan_id = 'load-capacity';

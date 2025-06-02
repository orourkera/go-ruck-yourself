-- SQL to create distinct weight achievements for metric and standard units
-- This maps exactly to the weight options available in the create session screen

-- First, let's see the current weight achievements that need to be split
SELECT achievement_key, name, description FROM achievements 
WHERE achievement_key IN (
  'light_starter', 'ten_pound_club', 'pack_pioneer', 'twenty_pound_warrior',
  'weight_warrior', 'thirty_pound_beast', 'heavy_hauler', 'forty_pound_hero',
  'beast_mode', 'ultra_heavy'
) ORDER BY achievement_key;

-- Create new achievement keys for metric weight achievements
-- Based on AppConfig.metricWeightOptions = [0.0, 2.6, 4.5, 9.0, 11.3, 13.6, 20.4, 22.7, 27.2]

INSERT INTO achievements (achievement_key, name, description, category, tier, criteria, icon_name, is_active, unit_preference)
VALUES
-- Metric weight achievements (kg)
('weight_2_6kg', 'Light Starter', 'Complete a ruck with 2.6kg (5.7lbs) weight', 'weight', 'bronze', '{"type": "session_weight", "target": 2.6}', 'weight', true, 'metric'),
('weight_4_5kg', 'Featherweight', 'Complete a ruck with 4.5kg (10lbs) weight', 'weight', 'bronze', '{"type": "session_weight", "target": 4.5}', 'weight', true, 'metric'),
('weight_9kg', 'Standard Bearer', 'Complete a ruck with 9kg (20lbs) weight', 'weight', 'silver', '{"type": "session_weight", "target": 9.0}', 'weight', true, 'metric'),
('weight_11_3kg', 'Pack Pioneer', 'Complete a ruck with 11.3kg (25lbs) weight', 'weight', 'silver', '{"type": "session_weight", "target": 11.3}', 'weight', true, 'metric'),
('weight_13_6kg', 'Weight Warrior', 'Complete a ruck with 13.6kg (30lbs) weight', 'weight', 'silver', '{"type": "session_weight", "target": 13.6}', 'weight', true, 'metric'),
('weight_20_4kg', 'Heavy Hauler', 'Complete a ruck with 20.4kg (45lbs) weight', 'weight', 'gold', '{"type": "session_weight", "target": 20.4}', 'weight', true, 'metric'),
('weight_22_7kg', 'Beast Mode', 'Complete a ruck with 22.7kg (50lbs) weight', 'weight', 'gold', '{"type": "session_weight", "target": 22.7}', 'weight', true, 'metric'),
('weight_27_2kg', 'Ultra Heavy', 'Complete a ruck with 27.2kg (60lbs) weight', 'weight', 'platinum', '{"type": "session_weight", "target": 27.2}', 'weight', true, 'metric');

-- Standard weight achievements (lbs) - Convert to kg for target since backend uses kg
-- Based on AppConfig.standardWeightOptions = [0.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 60.0]

INSERT INTO achievements (achievement_key, name, description, category, tier, criteria, icon_name, is_active, unit_preference)
VALUES
('weight_10lbs', 'Light Starter', 'Complete a ruck with 10lbs (4.5kg) weight', 'weight', 'bronze', '{"type": "session_weight", "target": 4.54}', 'weight', true, 'standard'),
('weight_15lbs', 'Featherweight', 'Complete a ruck with 15lbs (6.8kg) weight', 'weight', 'bronze', '{"type": "session_weight", "target": 6.80}', 'weight', true, 'standard'),
('weight_20lbs', 'Standard Bearer', 'Complete a ruck with 20lbs (9kg) weight', 'weight', 'silver', '{"type": "session_weight", "target": 9.07}', 'weight', true, 'standard'),
('weight_25lbs', 'Pack Pioneer', 'Complete a ruck with 25lbs (11.3kg) weight', 'weight', 'silver', '{"type": "session_weight", "target": 11.34}', 'weight', true, 'standard'),
('weight_30lbs', 'Weight Warrior', 'Complete a ruck with 30lbs (13.6kg) weight', 'weight', 'silver', '{"type": "session_weight", "target": 13.61}', 'weight', true, 'standard'),
('weight_35lbs', 'Thirty-Five Warrior', 'Complete a ruck with 35lbs (15.9kg) weight', 'weight', 'silver', '{"type": "session_weight", "target": 15.88}', 'weight', true, 'standard'),
('weight_40lbs', 'Heavy Hauler', 'Complete a ruck with 40lbs (18.1kg) weight', 'weight', 'gold', '{"type": "session_weight", "target": 18.14}', 'weight', true, 'standard'),
('weight_45lbs', 'Beast Mode', 'Complete a ruck with 45lbs (20.4kg) weight', 'weight', 'gold', '{"type": "session_weight", "target": 20.41}', 'weight', true, 'standard'),
('weight_50lbs', 'Fifty Pound Hero', 'Complete a ruck with 50lbs (22.7kg) weight', 'weight', 'gold', '{"type": "session_weight", "target": 22.68}', 'weight', true, 'standard'),
('weight_60lbs', 'Ultra Heavy', 'Complete a ruck with 60lbs (27.2kg) weight', 'weight', 'platinum', '{"type": "session_weight", "target": 27.22}', 'weight', true, 'standard');

-- Now deactivate the original universal weight achievements
UPDATE achievements 
SET is_active = false 
WHERE achievement_key IN (
  'light_starter', 'ten_pound_club', 'pack_pioneer', 'twenty_pound_warrior',
  'weight_warrior', 'thirty_pound_beast', 'heavy_hauler', 'forty_pound_hero',
  'beast_mode', 'ultra_heavy'
);

-- Verify the new achievements
SELECT achievement_key, name, criteria, unit_preference, description 
FROM achievements 
WHERE category = 'weight' AND is_active = true
ORDER BY unit_preference, (criteria->>'target')::numeric;

-- Show count of achievements by unit preference
SELECT 
  unit_preference,
  COUNT(*) as achievement_count
FROM achievements 
WHERE category = 'weight' AND is_active = true
GROUP BY unit_preference;

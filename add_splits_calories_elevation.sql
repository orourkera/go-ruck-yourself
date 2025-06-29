-- Migration to add calories_burned and elevation_gain_m columns to session_splits table
-- Run this SQL in your Supabase SQL editor

-- Add calories_burned column (float, nullable since older splits won't have this data)
ALTER TABLE session_splits 
ADD COLUMN calories_burned FLOAT;

-- Add elevation_gain_m column (float, nullable since older splits won't have this data)  
ALTER TABLE session_splits 
ADD COLUMN elevation_gain_m FLOAT;

-- Add comments for documentation
COMMENT ON COLUMN session_splits.calories_burned IS 'Calories burned during this specific split';
COMMENT ON COLUMN session_splits.elevation_gain_m IS 'Elevation gain in meters during this specific split';

-- Verify the changes
SELECT column_name, data_type, is_nullable, column_default 
FROM information_schema.columns 
WHERE table_name = 'session_splits' 
ORDER BY ordinal_position;

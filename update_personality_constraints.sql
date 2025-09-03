-- Migration: Update personality constraints to match frontend options
-- This fixes the database constraint that was preventing new personalities from being saved

-- Drop the existing constraint that only allows 4 old personalities
ALTER TABLE user_coaching_plans 
DROP CONSTRAINT valid_personality;

-- Add new constraint that matches the current frontend CoachingPersonality options
ALTER TABLE user_coaching_plans 
ADD CONSTRAINT valid_personality CHECK (coaching_personality IN (
    'Supportive Friend',
    'Drill Sergeant', 
    'Southern Redneck',
    'Yoga Instructor',
    'British Butler',
    'Sports Commentator',
    'Cowboy/Cowgirl',
    'Nature Lover',
    'Session Analyst'
));
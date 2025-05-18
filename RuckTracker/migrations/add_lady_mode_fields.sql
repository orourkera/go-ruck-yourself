-- Add new fields to user table for Lady Mode
ALTER TABLE "user" 
ADD COLUMN IF NOT EXISTS gender VARCHAR(10),
ADD COLUMN IF NOT EXISTS height_cm FLOAT,
ADD COLUMN IF NOT EXISTS allow_ruck_sharing BOOLEAN DEFAULT TRUE;

-- Update existing users to have default values
UPDATE "user" 
SET gender = 'male',
    allow_ruck_sharing = TRUE 
WHERE gender IS NULL;

-- Add comment explaining these fields
COMMENT ON COLUMN "user".gender IS 'User gender (male/female) for Lady Mode features';
COMMENT ON COLUMN "user".height_cm IS 'User height in centimeters';
COMMENT ON COLUMN "user".allow_ruck_sharing IS 'Whether the user allows sharing their rucking data';

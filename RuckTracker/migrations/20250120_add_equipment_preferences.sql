-- Add equipment preferences to user table
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS equipment_type TEXT CHECK (equipment_type IN ('ruck', 'vest', 'both', 'none')),
ADD COLUMN IF NOT EXISTS equipment_weight_kg DECIMAL(5,2) CHECK (equipment_weight_kg > 0 AND equipment_weight_kg <= 200);

-- Add comments for clarity
COMMENT ON COLUMN public.users.equipment_type IS 'User preferred equipment type: ruck (backpack), vest (weighted vest), both, or none';
COMMENT ON COLUMN public.users.equipment_weight_kg IS 'Maximum comfortable carrying weight in kilograms';
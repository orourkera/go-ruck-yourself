-- Add notification_first_ruck column to user table
-- This column controls whether users receive notifications when community members complete their first ruck

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user' 
        AND column_name = 'notification_first_ruck'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.user 
        ADD COLUMN notification_first_ruck boolean DEFAULT true;
    END IF;
END $$;

-- Add comment explaining the column
COMMENT ON COLUMN public.user.notification_first_ruck IS 'Whether user wants to receive notifications when community members complete their first ruck';
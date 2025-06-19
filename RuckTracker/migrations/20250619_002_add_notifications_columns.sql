-- Add missing columns to notifications table for events and clubs
-- This fixes the database trigger error when creating events

-- Add club_id column (optional, for club-related notifications)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'club_id'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications 
        ADD COLUMN club_id UUID REFERENCES public.clubs(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Add event_id column (optional, for event-related notifications)  
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'event_id'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications 
        ADD COLUMN event_id UUID REFERENCES public.events(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_notifications_club_id ON public.notifications(club_id);
CREATE INDEX IF NOT EXISTS idx_notifications_event_id ON public.notifications(event_id);

-- Add comment explaining the schema
COMMENT ON COLUMN public.notifications.club_id IS 'Reference to club for club-related notifications (optional)';
COMMENT ON COLUMN public.notifications.event_id IS 'Reference to event for event-related notifications (optional)';

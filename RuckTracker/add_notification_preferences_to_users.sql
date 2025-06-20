-- Add notification preference columns to user table
-- Run this migration to add the new notification preference fields

ALTER TABLE "user" 
ADD COLUMN notification_clubs BOOLEAN DEFAULT true,
ADD COLUMN notification_buddies BOOLEAN DEFAULT true,
ADD COLUMN notification_events BOOLEAN DEFAULT true,
ADD COLUMN notification_duels BOOLEAN DEFAULT true;

-- Add comments to document the purpose of each column
COMMENT ON COLUMN "user".notification_clubs IS 'Whether user wants to receive club-related notifications (membership updates, club events, discussions)';
COMMENT ON COLUMN "user".notification_buddies IS 'Whether user wants to receive ruck buddies notifications (likes, comments on ruck sessions)';
COMMENT ON COLUMN "user".notification_events IS 'Whether user wants to receive event notifications (invitations, updates, comments)';
COMMENT ON COLUMN "user".notification_duels IS 'Whether user wants to receive duel notifications (invitations, progress updates, completion)';

-- Create an index for faster queries on notification preferences (optional optimization)
CREATE INDEX idx_user_notification_preferences ON "user"(notification_clubs, notification_buddies, notification_events, notification_duels);

-- Add Strava integration columns to public.user table
ALTER TABLE public.user ADD COLUMN IF NOT EXISTS strava_access_token TEXT;
ALTER TABLE public.user ADD COLUMN IF NOT EXISTS strava_refresh_token TEXT;
ALTER TABLE public.user ADD COLUMN IF NOT EXISTS strava_expires_at BIGINT;
ALTER TABLE public.user ADD COLUMN IF NOT EXISTS strava_athlete_id BIGINT;
ALTER TABLE public.user ADD COLUMN IF NOT EXISTS strava_connected_at TIMESTAMP WITH TIME ZONE;

-- Add index on strava_athlete_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_user_strava_athlete_id ON public.user(strava_athlete_id);

-- Add index on strava_connected_at for analytics
CREATE INDEX IF NOT EXISTS idx_user_strava_connected_at ON public.user(strava_connected_at);

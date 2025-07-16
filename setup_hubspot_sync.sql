-- Create table to track HubSpot sync status
CREATE TABLE IF NOT EXISTS hubspot_sync_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    user_email TEXT NOT NULL,
    hubspot_contact_id TEXT,
    sync_status TEXT NOT NULL CHECK (sync_status IN ('success', 'error', 'pending')),
    error_message TEXT,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    data_synced JSONB
);

-- Enable RLS on the sync log table
ALTER TABLE hubspot_sync_log ENABLE ROW LEVEL SECURITY;

-- Create policy for sync log (only service role can access)
CREATE POLICY "Only service role can access sync log" ON hubspot_sync_log
    FOR ALL USING (auth.role() = 'service_role');

-- Create function to sync user to HubSpot
CREATE OR REPLACE FUNCTION sync_user_to_hubspot()
RETURNS TRIGGER AS $$
DECLARE
    user_display_name TEXT;
    user_device_type TEXT;
    hubspot_payload JSONB;
    hubspot_response TEXT;
    first_name TEXT;
    last_name TEXT;
    name_parts TEXT[];
BEGIN
    -- Get user profile data
    SELECT username
    INTO user_display_name
    FROM public.users
    WHERE id = NEW.id;
    
    -- Get device type from user_device_tokens (get the most recent one)
    SELECT device_type 
    INTO user_device_type
    FROM public.user_device_tokens 
    WHERE user_id = NEW.id 
    ORDER BY created_at DESC 
    LIMIT 1;
    
    -- Use email username if no display name
    IF user_display_name IS NULL OR user_display_name = '' THEN
        user_display_name := split_part(NEW.email, '@', 1);
    END IF;
    
    -- Parse name into first/last
    name_parts := string_to_array(user_display_name, ' ');
    first_name := COALESCE(name_parts[1], '');
    last_name := CASE 
        WHEN array_length(name_parts, 1) > 1 THEN 
            array_to_string(name_parts[2:], ' ')
        ELSE '' 
    END;
    
    -- Create HubSpot payload
    hubspot_payload := jsonb_build_object(
        'properties', jsonb_build_object(
            'email', NEW.email,
            'firstname', first_name,
            'lastname', last_name,
            'device_type', COALESCE(user_device_type, 'unknown'),
            'signup_date', NEW.created_at::text,
            'source', 'RuckingApp'
        )
    );
    
    -- Log the attempt
    INSERT INTO hubspot_sync_log (
        user_id, 
        user_email, 
        sync_status, 
        data_synced
    ) VALUES (
        NEW.id, 
        NEW.email, 
        'pending', 
        hubspot_payload
    );
    
    -- Make HTTP request to HubSpot API
    SELECT content INTO hubspot_response
    FROM http((
        'POST',
        'https://api.hubapi.com/crm/v3/objects/contacts',
        ARRAY[
            http_header('Authorization', 'Bearer ' || current_setting('app.hubspot_api_key')),
            http_header('Content-Type', 'application/json')
        ],
        'application/json',
        hubspot_payload::text
    ));
    
    -- Update sync status to success
    UPDATE hubspot_sync_log 
    SET 
        sync_status = 'success',
        hubspot_contact_id = (hubspot_response::jsonb->>'id'),
        synced_at = NOW()
    WHERE user_id = NEW.id 
    AND sync_status = 'pending';
    
    RETURN NEW;
    
EXCEPTION WHEN OTHERS THEN
    -- Log the error
    UPDATE hubspot_sync_log 
    SET 
        sync_status = 'error',
        error_message = SQLERRM,
        synced_at = NOW()
    WHERE user_id = NEW.id 
    AND sync_status = 'pending';
    
    -- Don't fail the user creation, just log the error
    RAISE WARNING 'Failed to sync user to HubSpot: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on auth.users table
CREATE TRIGGER sync_new_user_to_hubspot
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION sync_user_to_hubspot();

-- Set up the HubSpot API key (run this with your actual key)
-- ALTER DATABASE postgres SET "app.hubspot_api_key" = 'your_hubspot_api_key_here';

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO postgres;
GRANT ALL ON TABLE hubspot_sync_log TO postgres;
GRANT EXECUTE ON FUNCTION sync_user_to_hubspot() TO postgres;

-- Enable the http extension if not already enabled
CREATE EXTENSION IF NOT EXISTS http;

-- Test the function (optional)
-- SELECT sync_user_to_hubspot();

-- Create device tokens table and upsert function for Firebase push notifications

-- Create the device tokens table
CREATE TABLE IF NOT EXISTS user_device_tokens (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    device_id TEXT,
    device_type TEXT CHECK (device_type IN ('ios', 'android')),
    app_version TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user_id ON user_device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_tokens_fcm_token ON user_device_tokens(fcm_token);
CREATE INDEX IF NOT EXISTS idx_user_device_tokens_active ON user_device_tokens(is_active);

-- Create or replace the upsert function
CREATE OR REPLACE FUNCTION upsert_device_token(
    p_user_id UUID,
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT NULL,
    p_device_type TEXT DEFAULT NULL,
    p_app_version TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    token_id UUID;
BEGIN
    -- Try to update existing token first
    UPDATE user_device_tokens 
    SET 
        fcm_token = p_fcm_token,
        device_id = COALESCE(p_device_id, device_id),
        device_type = COALESCE(p_device_type, device_type),
        app_version = COALESCE(p_app_version, app_version),
        is_active = true,
        updated_at = NOW()
    WHERE user_id = p_user_id 
    AND (
        fcm_token = p_fcm_token 
        OR (device_id IS NOT NULL AND device_id = p_device_id)
    )
    RETURNING id INTO token_id;
    
    -- If no existing token was updated, insert a new one
    IF token_id IS NULL THEN
        INSERT INTO user_device_tokens (
            user_id, 
            fcm_token, 
            device_id, 
            device_type, 
            app_version,
            is_active
        ) VALUES (
            p_user_id, 
            p_fcm_token, 
            p_device_id, 
            p_device_type, 
            p_app_version,
            true
        )
        RETURNING id INTO token_id;
    END IF;
    
    RETURN token_id;
END;
$$;

-- Create a trigger to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_user_device_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_device_tokens_updated_at ON user_device_tokens;
CREATE TRIGGER trigger_update_user_device_tokens_updated_at
    BEFORE UPDATE ON user_device_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_user_device_tokens_updated_at();

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON user_device_tokens TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_device_tokens TO authenticated;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;

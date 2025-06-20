-- Step 2: Create the upsert function
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

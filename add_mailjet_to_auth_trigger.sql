-- ADD MAILJET SYNC TO AUTH TRIGGER
-- This modifies the existing handle_new_user() trigger to automatically sync new users to Mailjet
-- Works for ALL signup methods: API, OAuth, direct Supabase auth

-- First, enable the http extension if not already enabled
CREATE EXTENSION IF NOT EXISTS http;

-- Update the handle_new_user function to include Mailjet sync
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    mailjet_response http_response;
    mailjet_payload jsonb;
    username_value text;
BEGIN
    -- Skip if user already exists
    IF EXISTS (SELECT 1 FROM public.user WHERE id = NEW.id) THEN
        RETURN NEW;
    END IF;
    
    -- Only create user if we have valid email
    IF NEW.email IS NOT NULL AND NEW.email != '' THEN
        -- Extract username for both user creation and Mailjet
        username_value := COALESCE(
            NEW.raw_user_meta_data->>'display_name',
            NEW.raw_user_meta_data->>'full_name', 
            NEW.raw_user_meta_data->>'name',
            SPLIT_PART(NEW.email, '@', 1),
            'User'
        );
        
        -- Create user in public.user table
        INSERT INTO public.user (
            id,
            email,
            username,
            prefer_metric,
            avatar_url,
            created_at,
            updated_at
        )
        VALUES (
            NEW.id,
            NEW.email,
            username_value,
            true,  -- Default to metric = true
            NEW.raw_user_meta_data->>'avatar_url',
            NEW.created_at,
            NOW()
        )
        ON CONFLICT (id) DO NOTHING;
        
        -- Sync to Mailjet via HTTP call to our Flask API
        BEGIN
            -- Prepare Mailjet payload
            mailjet_payload := jsonb_build_object(
                'email', NEW.email,
                'username', username_value,
                'user_metadata', jsonb_build_object(
                    'user_id', NEW.id::text,
                    'signup_date', to_char(NEW.created_at, 'DD/MM/YYYY'),
                    'signup_source', CASE 
                        WHEN NEW.raw_user_meta_data->>'provider' = 'google' THEN 'google_oauth'
                        WHEN NEW.raw_user_meta_data->>'provider' = 'apple' THEN 'apple_oauth'
                        ELSE 'database_trigger'
                    END,
                    'name', username_value,
                    'firstname', SPLIT_PART(username_value, ' ', 1)
                )
            );
            
            -- Make HTTP call to our internal Mailjet sync endpoint
            SELECT http_post(
                'https://getrucky.com/api/internal/mailjet-sync',
                mailjet_payload::text,
                'application/json'
            ) INTO mailjet_response;
            
            -- Log success/failure (don't fail user creation if Mailjet fails)
            IF mailjet_response.status = 200 THEN
                RAISE NOTICE 'Mailjet sync successful for user: %', NEW.email;
            ELSE
                RAISE WARNING 'Mailjet sync failed for user %, status: %, response: %', 
                    NEW.email, mailjet_response.status, mailjet_response.content;
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            -- Don't fail user creation if Mailjet sync fails
            RAISE WARNING 'Mailjet sync error for user %: %', NEW.email, SQLERRM;
        END;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Verify the trigger exists (it should already be there)
SELECT 'Trigger updated successfully! New users will automatically sync to Mailjet.' as status;

-- Test query to see recent users
SELECT 
    'Recent users (should auto-sync to Mailjet)' as status,
    u.email,
    u.username,
    u.created_at
FROM public.user u
ORDER BY u.created_at DESC
LIMIT 5;

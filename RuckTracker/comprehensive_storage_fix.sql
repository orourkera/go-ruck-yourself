-- Comprehensive fix for event banner storage issues
-- Run this in your Supabase SQL Editor

-- 1. First, let's see what buckets exist
-- SELECT * FROM storage.buckets;

-- 2. Drop ALL storage policies to start fresh
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    -- Drop all policies on storage.objects table
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'objects' AND schemaname = 'storage'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || policy_record.policyname || '" ON storage.objects';
    END LOOP;
END $$;

-- 3. Create the event-banners bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'event-banners', 
    'event-banners', 
    true, 
    10485760, -- 10MB limit
    array['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];

-- 4. Create minimal but comprehensive policies
-- Allow anyone to view event banners
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'event-banners');

-- Allow authenticated users to do everything with event banners
CREATE POLICY "Authenticated Full Access"
ON storage.objects FOR ALL
TO authenticated
USING (bucket_id = 'event-banners')
WITH CHECK (bucket_id = 'event-banners');

-- 5. Enable RLS on storage.objects (should already be enabled but just in case)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 6. Grant necessary permissions to authenticated role
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;

-- Debug and fix storage policies for event_banners
-- Run this in your Supabase SQL Editor

-- 1. Check what buckets exist
SELECT id, name, public FROM storage.buckets WHERE name LIKE '%event%';

-- 2. Check what policies exist for storage.objects
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'objects' AND schemaname = 'storage';

-- 3. Drop ALL existing policies for storage.objects to start fresh
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'objects' AND schemaname = 'storage'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || policy_record.policyname || '" ON storage.objects';
        RAISE NOTICE 'Dropped policy: %', policy_record.policyname;
    END LOOP;
END $$;

-- 4. Create super simple policies that definitely work
-- Allow all authenticated users to do everything in event_banners bucket
CREATE POLICY "event_banners_all_access"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'event_banners')
WITH CHECK (bucket_id = 'event_banners');

-- Allow public to read event banners
CREATE POLICY "event_banners_public_read"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'event_banners');

-- 5. Verify the policies were created
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname LIKE '%event%';

-- Create policies for event_banners bucket
-- Run this in your Supabase SQL Editor

-- Allow public read access to event banners
CREATE POLICY "Allow public read access"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'event_banners');

-- Allow authenticated users to upload event banners
CREATE POLICY "Allow authenticated uploads"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'event_banners');

-- Allow authenticated users to update event banners
CREATE POLICY "Allow authenticated updates"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'event_banners')
WITH CHECK (bucket_id = 'event_banners');

-- Allow authenticated users to delete event banners
CREATE POLICY "Allow authenticated deletes"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'event_banners');

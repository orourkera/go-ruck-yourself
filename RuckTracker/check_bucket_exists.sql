-- Check if event_banners bucket exists and its configuration
-- Run this in your Supabase SQL Editor

-- 1. List ALL buckets to see what exists
SELECT id, name, public, file_size_limit, allowed_mime_types, created_at 
FROM storage.buckets 
ORDER BY name;

-- 2. Check specifically for event_banners bucket
SELECT id, name, public, file_size_limit, allowed_mime_types, created_at 
FROM storage.buckets 
WHERE name = 'event_banners';

-- 3. If the bucket doesn't exist, create it
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'event_banners', 
    'event_banners', 
    true, 
    10485760, -- 10MB limit
    array['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];

-- 4. Verify bucket exists after creation
SELECT id, name, public, file_size_limit, allowed_mime_types 
FROM storage.buckets 
WHERE name = 'event_banners';

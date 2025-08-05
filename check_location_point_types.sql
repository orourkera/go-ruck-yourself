-- Check the actual data types in location_point table
SELECT 
    column_name, 
    data_type,
    character_maximum_length,
    numeric_precision,
    numeric_scale
FROM information_schema.columns 
WHERE table_name = 'location_point' 
ORDER BY ordinal_position;

-- Check a sample row to see actual data
SELECT 
    id,
    session_id,
    pg_typeof(latitude) as latitude_type,
    pg_typeof(longitude) as longitude_type,
    pg_typeof(altitude) as altitude_type,
    pg_typeof(timestamp) as timestamp_type,
    latitude,
    longitude,
    altitude,
    timestamp
FROM location_point 
WHERE session_id = 669
LIMIT 1; 
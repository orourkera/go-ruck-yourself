-- Check the actual schema of location_point table
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'location_point' 
ORDER BY ordinal_position;

-- Also check a sample of the data
SELECT * FROM location_point LIMIT 5;

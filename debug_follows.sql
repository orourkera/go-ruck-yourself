-- Debug script to check user follows
-- Replace with actual user ID: 11683829-2c73-46fc-82f1-f905d5316c30

-- Check if user_follows table exists and has data
SELECT COUNT(*) as total_follows FROM user_follows;

-- Check follows for specific user
SELECT * FROM user_follows 
WHERE follower_id = '11683829-2c73-46fc-82f1-f905d5316c30';

-- Check if this user is being followed by others
SELECT * FROM user_follows 
WHERE followed_id = '11683829-2c73-46fc-82f1-f905d5316c30';

-- Test the array query used in the function
SELECT ARRAY(
    SELECT followed_id 
    FROM user_follows 
    WHERE follower_id = '11683829-2c73-46fc-82f1-f905d5316c30'
) as following_user_ids;

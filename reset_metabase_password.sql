-- Reset Metabase admin password to 'admin123'
-- The password will be hashed using bcrypt
UPDATE core_user
SET password_hash = '$2a$10$ZJ9V.SuHfW1ExZTM1tLqu.oZkMRr8vWI5Y9wV4dsTn.Ug4eG6Wdqm'
WHERE email = 'admin@metabase.local' OR is_superuser = true;

-- Show the updated user to confirm
SELECT id, email, first_name, last_name, is_superuser
FROM core_user
WHERE is_superuser = true;
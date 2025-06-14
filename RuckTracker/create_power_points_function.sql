-- SQL function to efficiently calculate total power points for a user
-- This function runs directly in the database for better performance

CREATE OR REPLACE FUNCTION calculate_user_power_points(user_id_param UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(CAST(power_points AS NUMERIC))
         FROM ruck_session 
         WHERE user_id = user_id_param 
         AND status = 'completed'
         AND power_points IS NOT NULL
         AND power_points != ''), 
        0
    );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION calculate_user_power_points(UUID) TO authenticated;

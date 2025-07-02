-- Create missing Postgres functions for achievement system

-- Function to calculate user's total distance
CREATE OR REPLACE FUNCTION get_user_total_distance(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    total_distance numeric := 0;
BEGIN
    SELECT COALESCE(SUM(distance_km), 0)
    INTO total_distance
    FROM ruck_session
    WHERE user_id = p_user_id AND status = 'completed';
    
    RETURN total_distance;
END;
$$;

-- Function to calculate user's total power points
CREATE OR REPLACE FUNCTION calculate_user_power_points(user_id_param uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    total_power_points numeric := 0;
BEGIN
    SELECT COALESCE(SUM(power_points), 0)
    INTO total_power_points
    FROM ruck_session
    WHERE user_id = user_id_param AND status = 'completed';
    
    RETURN total_power_points;
END;
$$;

-- Function to count sessions before a certain hour
CREATE OR REPLACE FUNCTION count_sessions_before_hour(p_user_id uuid, p_hour integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    session_count integer := 0;
BEGIN
    SELECT COUNT(*)
    INTO session_count
    FROM ruck_session
    WHERE user_id = p_user_id 
    AND status = 'completed'
    AND EXTRACT(HOUR FROM started_at::timestamp) < p_hour;
    
    RETURN session_count;
END;
$$;

-- Function to count sessions after a certain hour
CREATE OR REPLACE FUNCTION count_sessions_after_hour(p_user_id uuid, p_hour integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    session_count integer := 0;
BEGIN
    SELECT COUNT(*)
    INTO session_count
    FROM ruck_session
    WHERE user_id = p_user_id 
    AND status = 'completed'
    AND EXTRACT(HOUR FROM started_at::timestamp) > p_hour;
    
    RETURN session_count;
END;
$$;

-- Function to get monthly distance for a user
CREATE OR REPLACE FUNCTION get_user_monthly_distance(p_user_id uuid, p_year integer, p_month integer)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    monthly_distance numeric := 0;
BEGIN
    SELECT COALESCE(SUM(distance_km), 0)
    INTO monthly_distance
    FROM ruck_session
    WHERE user_id = p_user_id 
    AND status = 'completed'
    AND EXTRACT(YEAR FROM started_at::timestamp) = p_year
    AND EXTRACT(MONTH FROM started_at::timestamp) = p_month;
    
    RETURN monthly_distance;
END;
$$;

-- Function to get quarterly distance for a user
CREATE OR REPLACE FUNCTION get_user_quarterly_distance(p_user_id uuid, p_year integer, p_quarter integer)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    quarterly_distance numeric := 0;
    start_month integer;
    end_month integer;
BEGIN
    -- Calculate start and end months for the quarter
    start_month := (p_quarter - 1) * 3 + 1;
    end_month := p_quarter * 3;
    
    SELECT COALESCE(SUM(distance_km), 0)
    INTO quarterly_distance
    FROM ruck_session
    WHERE user_id = p_user_id 
    AND status = 'completed'
    AND EXTRACT(YEAR FROM started_at::timestamp) = p_year
    AND EXTRACT(MONTH FROM started_at::timestamp) BETWEEN start_month AND end_month;
    
    RETURN quarterly_distance;
END;
$$;

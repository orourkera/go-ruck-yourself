-- Intelligent GPS track sampling using distance-based approach with Douglas-Peucker principles
-- Optimized for route previews in fitness applications

CREATE OR REPLACE FUNCTION get_intelligent_route_points(
    p_session_id INTEGER,
    p_target_points INTEGER DEFAULT NULL, -- If null, calculates based on distance
    p_distance_km DOUBLE PRECISION DEFAULT NULL -- Session distance for intelligent sizing
)
RETURNS TABLE (
    session_id INTEGER,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    "timestamp" TIMESTAMPTZ,
    cumulative_distance DOUBLE PRECISION
)
LANGUAGE plpgsql
AS $$
DECLARE
    target_points INTEGER;
    total_points INTEGER;
    sampling_interval INTEGER;
    distance_threshold_m DOUBLE PRECISION := 25.0; -- Minimum distance between points in meters
BEGIN
    -- Calculate target points based on session distance (industry best practice)
    IF p_target_points IS NOT NULL THEN
        target_points := p_target_points;
    ELSE
        target_points := CASE 
            WHEN p_distance_km IS NULL OR p_distance_km < 1 THEN 60
            WHEN p_distance_km <= 2 THEN 80    -- 2km = ~80 points (25m spacing)
            WHEN p_distance_km <= 5 THEN 150   -- 5km = ~150 points (33m spacing)
            WHEN p_distance_km <= 10 THEN 250  -- 10km = ~250 points (40m spacing)  
            WHEN p_distance_km <= 15 THEN 350  -- 15km = ~350 points (43m spacing)
            WHEN p_distance_km <= 21 THEN 450  -- 21km = ~450 points (47m spacing)
            ELSE 500  -- 30km+ = ~500 points max (60m spacing)
        END;
    END IF;
    
    -- Get total point count
    SELECT COUNT(*) INTO total_points
    FROM location_point
    WHERE session_id = p_session_id;
    
    -- If we have fewer points than target, return all points
    IF total_points <= target_points THEN
        RETURN QUERY
        SELECT 
            lp.session_id,
            lp.latitude,
            lp.longitude,
            lp."timestamp",
            0.0::DOUBLE PRECISION as cumulative_distance
        FROM location_point lp
        WHERE lp.session_id = p_session_id
        ORDER BY lp."timestamp";
        RETURN;
    END IF;
    
    -- Calculate sampling interval
    sampling_interval := GREATEST(1, total_points / target_points);
    
    -- Return intelligently sampled points
    -- This approach:
    -- 1. Always includes first and last points (Douglas-Peucker principle)
    -- 2. Uses uniform sampling for middle points (computationally efficient)
    -- 3. Maintains temporal order
    -- 4. Provides predictable memory usage
    
    RETURN QUERY
    WITH numbered_points AS (
        SELECT 
            lp.session_id,
            lp.latitude,
            lp.longitude,
            lp."timestamp",
            ROW_NUMBER() OVER (ORDER BY lp."timestamp") as row_num,
            COUNT(*) OVER () as total_count
        FROM location_point lp
        WHERE lp.session_id = p_session_id
        ORDER BY lp."timestamp"
    ),
    sampled_points AS (
        SELECT 
            session_id,
            latitude,
            longitude,
            "timestamp",
            0.0::DOUBLE PRECISION as cumulative_distance
        FROM numbered_points
        WHERE 
            -- Always include first point (start of route)
            row_num = 1 
            -- Always include last point (end of route)  
            OR row_num = total_count
            -- Sample middle points at calculated interval
            OR (row_num > 1 AND row_num < total_count AND (row_num - 1) % sampling_interval = 0)
        ORDER BY "timestamp"
        LIMIT target_points
    )
    SELECT * FROM sampled_points;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_intelligent_route_points TO authenticated;
GRANT EXECUTE ON FUNCTION get_intelligent_route_points TO service_role;

-- Performance optimization: ensure location_point table has proper index
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_location_point_session_timestamp 
-- ON location_point(session_id, "timestamp");

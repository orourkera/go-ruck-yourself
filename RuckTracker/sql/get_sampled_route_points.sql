-- Function to intelligently sample route points for memory efficiency
-- while preserving the overall route shape

CREATE OR REPLACE FUNCTION get_sampled_route_points(
    p_session_id INTEGER,
    p_interval INTEGER DEFAULT 5,
    p_max_points INTEGER DEFAULT 200
)
RETURNS TABLE (
    session_id INTEGER,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    "timestamp" TIMESTAMP
)
LANGUAGE sql
AS $$
    WITH numbered_points AS (
        SELECT 
            lp.session_id,
            lp.latitude::DOUBLE PRECISION,
            lp.longitude::DOUBLE PRECISION,
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
            "timestamp"
        FROM numbered_points
        WHERE 
            -- Always include first and last points
            row_num = 1 
            OR row_num = total_count
            -- Include evenly distributed points based on interval
            OR (row_num - 1) % p_interval = 0
        ORDER BY "timestamp"
        LIMIT p_max_points
    )
    SELECT * FROM sampled_points;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_sampled_route_points TO authenticated;
GRANT EXECUTE ON FUNCTION get_sampled_route_points TO service_role;

-- Function to privacy-clip the first and last N meters of a route, then sample points
-- Uses a Haversine implementation in SQL (no PostGIS dependency)

CREATE OR REPLACE FUNCTION get_privacy_clipped_sampled_points(
    p_session_id INTEGER,
    p_clip_meters DOUBLE PRECISION DEFAULT 250.0,
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
    WITH ordered AS (
        SELECT 
            lp.session_id,
            lp.latitude::DOUBLE PRECISION AS lat,
            lp.longitude::DOUBLE PRECISION AS lng,
            lp."timestamp"
        FROM location_point lp
        WHERE lp.session_id = p_session_id
        ORDER BY lp."timestamp"
    ),
    with_prev AS (
        SELECT 
            o.*,
            LAG(o.lat) OVER (ORDER BY o."timestamp") AS prev_lat,
            LAG(o.lng) OVER (ORDER BY o."timestamp") AS prev_lng
        FROM ordered o
    ),
    seg_dist AS (
        SELECT 
            session_id,
            lat,
            lng,
            "timestamp",
            -- Haversine distance in meters between current and previous point
            CASE 
                WHEN prev_lat IS NULL OR prev_lng IS NULL THEN 0
                ELSE (
                    2 * 6371000 * ASIN(
                        SQRT(
                            POWER(SIN(RADIANS((lat - prev_lat) / 2)), 2) +
                            COS(RADIANS(prev_lat)) * COS(RADIANS(lat)) * POWER(SIN(RADIANS((lng - prev_lng) / 2)), 2)
                        )
                    )
                )
            END AS d_from_prev
        FROM with_prev
    ),
    cum_forward AS (
        SELECT 
            *,
            SUM(d_from_prev) OVER (ORDER BY "timestamp" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_from_start
        FROM seg_dist
    ),
    cum_bidir AS (
        SELECT 
            *,
            SUM(d_from_prev) OVER (ORDER BY "timestamp" DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_from_end
        FROM cum_forward
    ),
    clipped AS (
        SELECT *
        FROM cum_bidir
        WHERE cum_from_start >= p_clip_meters
          AND cum_from_end   >= p_clip_meters
    ),
    numbered AS (
        SELECT 
            session_id,
            lat AS latitude,
            lng AS longitude,
            "timestamp",
            ROW_NUMBER() OVER (ORDER BY "timestamp") AS row_num,
            COUNT(*) OVER () AS total_count
        FROM clipped
    ),
    sampled AS (
        SELECT 
            session_id,
            latitude,
            longitude,
            "timestamp"
        FROM numbered
        WHERE 
            -- Always include first and last from the clipped set
            row_num = 1 OR row_num = total_count
            -- Include evenly distributed points based on interval
            OR (row_num - 1) % GREATEST(p_interval, 1) = 0
        ORDER BY "timestamp"
        LIMIT p_max_points
    )
    SELECT * FROM sampled;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION get_privacy_clipped_sampled_points TO authenticated;
GRANT EXECUTE ON FUNCTION get_privacy_clipped_sampled_points TO service_role;

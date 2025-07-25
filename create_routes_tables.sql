-- Migration: Create Routes and Related Tables with RLS
-- Date: 2025-01-25
-- Description: Create shareable route system for AllTrails integration

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ========================================
-- 1. ROUTES TABLE (Core shareable route data)
-- ========================================

CREATE TABLE IF NOT EXISTS routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    source VARCHAR(50) NOT NULL CHECK (source IN ('alltrails', 'custom', 'community')),
    external_id VARCHAR(255), -- AllTrails trail ID, etc.
    external_url TEXT, -- Link back to original source
    
    -- Geographic data
    start_latitude DECIMAL(10, 8) NOT NULL CHECK (start_latitude >= -90 AND start_latitude <= 90),
    start_longitude DECIMAL(11, 8) NOT NULL CHECK (start_longitude >= -180 AND start_longitude <= 180),
    end_latitude DECIMAL(10, 8) CHECK (end_latitude >= -90 AND end_latitude <= 90),
    end_longitude DECIMAL(11, 8) CHECK (end_longitude >= -180 AND end_longitude <= 180),
    route_polyline TEXT NOT NULL, -- Encoded polyline or GeoJSON
    
    -- Route metrics
    distance_km DECIMAL(6, 2) NOT NULL CHECK (distance_km > 0),
    elevation_gain_m DECIMAL(6, 1) NOT NULL DEFAULT 0 CHECK (elevation_gain_m >= 0),
    elevation_loss_m DECIMAL(6, 1) CHECK (elevation_loss_m >= 0),
    min_elevation_m DECIMAL(6, 1),
    max_elevation_m DECIMAL(6, 1),
    
    -- Difficulty and characteristics
    trail_difficulty VARCHAR(20) CHECK (trail_difficulty IN ('easy', 'moderate', 'hard', 'extreme')),
    trail_type VARCHAR(50) CHECK (trail_type IN ('loop', 'out_and_back', 'point_to_point')),
    surface_type VARCHAR(50) CHECK (surface_type IN ('trail', 'paved', 'gravel', 'mixed', 'rocky', 'technical')),
    
    -- Popularity metrics
    total_planned_count INTEGER DEFAULT 0 CHECK (total_planned_count >= 0),
    total_completed_count INTEGER DEFAULT 0 CHECK (total_completed_count >= 0),
    average_rating DECIMAL(3, 2) CHECK (average_rating >= 1.0 AND average_rating <= 5.0),
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by_user_id UUID REFERENCES auth.users(id),
    is_verified BOOLEAN DEFAULT FALSE,
    is_public BOOLEAN DEFAULT TRUE,
    
    -- Constraints
    CONSTRAINT unique_external_route UNIQUE (source, external_id),
    CONSTRAINT valid_elevation_range CHECK (min_elevation_m <= max_elevation_m)
);

-- Enable RLS on routes
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;

-- RLS Policies for routes
CREATE POLICY "Public routes are viewable by everyone"
    ON routes FOR SELECT
    USING (is_public = true);

CREATE POLICY "Users can view their own routes"
    ON routes FOR SELECT
    USING (auth.uid() = created_by_user_id);

CREATE POLICY "Authenticated users can create routes"
    ON routes FOR INSERT
    WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = created_by_user_id);

CREATE POLICY "Users can update their own routes"
    ON routes FOR UPDATE
    USING (auth.uid() = created_by_user_id)
    WITH CHECK (auth.uid() = created_by_user_id);

CREATE POLICY "Users can delete their own routes"
    ON routes FOR DELETE
    USING (auth.uid() = created_by_user_id);

-- ========================================
-- 2. ROUTE ELEVATION POINTS TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS route_elevation_point (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    distance_km DECIMAL(6, 3) NOT NULL CHECK (distance_km >= 0),
    elevation_m DECIMAL(6, 1) NOT NULL,
    latitude DECIMAL(10, 8) CHECK (latitude >= -90 AND latitude <= 90),
    longitude DECIMAL(11, 8) CHECK (longitude >= -180 AND longitude <= 180),
    terrain_type VARCHAR(50) CHECK (terrain_type IN ('trail', 'rocky', 'steep', 'technical', 'paved', 'gravel')),
    grade_percent DECIMAL(4, 1) CHECK (grade_percent >= -100 AND grade_percent <= 100),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on route_elevation_point
ALTER TABLE route_elevation_point ENABLE ROW LEVEL SECURITY;

-- RLS Policies for route_elevation_point
CREATE POLICY "Elevation points viewable if route is viewable"
    ON route_elevation_point FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_elevation_point.route_id
            AND (r.is_public = true OR r.created_by_user_id = auth.uid())
        )
    );

CREATE POLICY "Users can create elevation points for their routes"
    ON route_elevation_point FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_elevation_point.route_id
            AND r.created_by_user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update elevation points for their routes"
    ON route_elevation_point FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_elevation_point.route_id
            AND r.created_by_user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete elevation points for their routes"
    ON route_elevation_point FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_elevation_point.route_id
            AND r.created_by_user_id = auth.uid()
        )
    );

-- ========================================
-- 3. ROUTE POINTS OF INTEREST TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS route_point_of_interest (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    poi_type VARCHAR(50) NOT NULL CHECK (poi_type IN ('water', 'rest', 'viewpoint', 'hazard', 'parking', 'landmark', 'shelter')),
    latitude DECIMAL(10, 8) NOT NULL CHECK (latitude >= -90 AND latitude <= 90),
    longitude DECIMAL(11, 8) NOT NULL CHECK (longitude >= -180 AND longitude <= 180),
    distance_from_start_km DECIMAL(6, 3) CHECK (distance_from_start_km >= 0),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on route_point_of_interest
ALTER TABLE route_point_of_interest ENABLE ROW LEVEL SECURITY;

-- RLS Policies for route_point_of_interest
CREATE POLICY "POIs viewable if route is viewable"
    ON route_point_of_interest FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_point_of_interest.route_id
            AND (r.is_public = true OR r.created_by_user_id = auth.uid())
        )
    );

CREATE POLICY "Users can create POIs for their routes"
    ON route_point_of_interest FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_point_of_interest.route_id
            AND r.created_by_user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update POIs for their routes"
    ON route_point_of_interest FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_point_of_interest.route_id
            AND r.created_by_user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete POIs for their routes"
    ON route_point_of_interest FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_point_of_interest.route_id
            AND r.created_by_user_id = auth.uid()
        )
    );

-- ========================================
-- 4. PLANNED RUCK TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS planned_ruck (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    
    -- User-specific planning data
    name VARCHAR(255), -- Custom name override
    planned_date TIMESTAMPTZ,
    planned_ruck_weight_kg DECIMAL(4, 1) NOT NULL CHECK (planned_ruck_weight_kg > 0),
    planned_difficulty VARCHAR(20) NOT NULL CHECK (planned_difficulty IN ('easy', 'moderate', 'hard', 'extreme')),
    
    -- User preferences for this ruck
    safety_tracking_enabled BOOLEAN DEFAULT TRUE,
    weather_alerts_enabled BOOLEAN DEFAULT TRUE,
    notes TEXT,
    
    -- Calculated projections based on user profile + route
    estimated_duration_hours DECIMAL(4, 2) CHECK (estimated_duration_hours > 0),
    estimated_calories INTEGER CHECK (estimated_calories > 0),
    estimated_difficulty_description TEXT,
    
    -- Status tracking
    status VARCHAR(20) DEFAULT 'planned' CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on planned_ruck
ALTER TABLE planned_ruck ENABLE ROW LEVEL SECURITY;

-- RLS Policies for planned_ruck
CREATE POLICY "Users can only see their own planned rucks"
    ON planned_ruck FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own planned rucks"
    ON planned_ruck FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own planned rucks"
    ON planned_ruck FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own planned rucks"
    ON planned_ruck FOR DELETE
    USING (auth.uid() = user_id);

-- ========================================
-- 5. ROUTE ANALYTICS TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS route_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN ('planned', 'started', 'completed', 'cancelled', 'viewed')),
    
    -- Session-specific data (when applicable)
    actual_duration_hours DECIMAL(4, 2) CHECK (actual_duration_hours > 0),
    actual_ruck_weight_kg DECIMAL(4, 1) CHECK (actual_ruck_weight_kg > 0),
    user_rating INTEGER CHECK (user_rating >= 1 AND user_rating <= 5),
    user_feedback TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    UNIQUE(route_id, user_id, event_type, created_at)
);

-- Enable RLS on route_analytics
ALTER TABLE route_analytics ENABLE ROW LEVEL SECURITY;

-- RLS Policies for route_analytics
CREATE POLICY "Users can view analytics for public routes"
    ON route_analytics FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM routes r
            WHERE r.id = route_analytics.route_id
            AND r.is_public = true
        )
    );

CREATE POLICY "Users can view their own analytics"
    ON route_analytics FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own analytics"
    ON route_analytics FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ========================================
-- 6. UPDATE EXISTING TABLES
-- ========================================

-- Add route references to existing ruck_session table (singular)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ruck_session' AND column_name = 'route_id') THEN
        ALTER TABLE ruck_session ADD COLUMN route_id UUID REFERENCES routes(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ruck_session' AND column_name = 'planned_ruck_id') THEN
        ALTER TABLE ruck_session ADD COLUMN planned_ruck_id UUID REFERENCES planned_ruck(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ruck_session' AND column_name = 'is_guided_session') THEN
        ALTER TABLE ruck_session ADD COLUMN is_guided_session BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- ========================================
-- 7. CREATE INDEXES FOR PERFORMANCE
-- ========================================

-- Routes table indexes
CREATE INDEX IF NOT EXISTS idx_routes_location 
    ON routes USING GIST (ST_Point(start_longitude, start_latitude));

CREATE INDEX IF NOT EXISTS idx_routes_distance 
    ON routes(distance_km);

CREATE INDEX IF NOT EXISTS idx_routes_difficulty 
    ON routes(trail_difficulty) WHERE trail_difficulty IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_routes_popularity 
    ON routes(total_completed_count DESC, total_planned_count DESC);

CREATE INDEX IF NOT EXISTS idx_routes_source_external 
    ON routes(source, external_id) WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_routes_public_verified 
    ON routes(is_public, is_verified);

CREATE INDEX IF NOT EXISTS idx_routes_created_by 
    ON routes(created_by_user_id) WHERE created_by_user_id IS NOT NULL;

-- Route elevation points indexes
CREATE INDEX IF NOT EXISTS idx_elevation_points_route_distance 
    ON route_elevation_point(route_id, distance_km);

CREATE INDEX IF NOT EXISTS idx_elevation_points_route 
    ON route_elevation_point(route_id);

-- Route POI indexes
CREATE INDEX IF NOT EXISTS idx_poi_route 
    ON route_point_of_interest(route_id);

CREATE INDEX IF NOT EXISTS idx_poi_type 
    ON route_point_of_interest(poi_type);

CREATE INDEX IF NOT EXISTS idx_poi_location 
    ON route_point_of_interest USING GIST (ST_Point(longitude, latitude));

-- Planned ruck indexes
CREATE INDEX IF NOT EXISTS idx_planned_ruck_user_status 
    ON planned_ruck(user_id, status);

CREATE INDEX IF NOT EXISTS idx_planned_ruck_user_date 
    ON planned_ruck(user_id, planned_date) WHERE planned_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_planned_ruck_route 
    ON planned_ruck(route_id);

CREATE INDEX IF NOT EXISTS idx_planned_ruck_status 
    ON planned_ruck(status);

-- Route analytics indexes
CREATE INDEX IF NOT EXISTS idx_analytics_route_event 
    ON route_analytics(route_id, event_type, created_at);

CREATE INDEX IF NOT EXISTS idx_analytics_user 
    ON route_analytics(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_analytics_route_ratings 
    ON route_analytics(route_id, user_rating) WHERE user_rating IS NOT NULL;

-- Enhanced ruck_session indexes (singular table name)
CREATE INDEX IF NOT EXISTS idx_ruck_session_route 
    ON ruck_session(route_id) WHERE route_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ruck_session_planned_ruck 
    ON ruck_session(planned_ruck_id) WHERE planned_ruck_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ruck_session_guided 
    ON ruck_session(is_guided_session) WHERE is_guided_session = true;

-- ========================================
-- 8. CREATE FUNCTIONS AND TRIGGERS
-- ========================================

-- Function to update route popularity metrics
CREATE OR REPLACE FUNCTION update_route_popularity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.event_type = 'planned' THEN
            UPDATE routes 
            SET total_planned_count = total_planned_count + 1
            WHERE id = NEW.route_id;
        ELSIF NEW.event_type = 'completed' THEN
            UPDATE routes 
            SET total_completed_count = total_completed_count + 1
            WHERE id = NEW.route_id;
        END IF;
        
        -- Update average rating if rating provided
        IF NEW.user_rating IS NOT NULL THEN
            UPDATE routes 
            SET average_rating = (
                SELECT AVG(user_rating::decimal)
                FROM route_analytics 
                WHERE route_id = NEW.route_id 
                AND user_rating IS NOT NULL
            )
            WHERE id = NEW.route_id;
        END IF;
        
        RETURN NEW;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update route popularity
DROP TRIGGER IF EXISTS trigger_update_route_popularity ON route_analytics;
CREATE TRIGGER trigger_update_route_popularity
    AFTER INSERT ON route_analytics
    FOR EACH ROW
    EXECUTE FUNCTION update_route_popularity();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS trigger_routes_updated_at ON routes;
CREATE TRIGGER trigger_routes_updated_at
    BEFORE UPDATE ON routes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_planned_ruck_updated_at ON planned_ruck;
CREATE TRIGGER trigger_planned_ruck_updated_at
    BEFORE UPDATE ON planned_ruck
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ========================================
-- 9. ADDITIONAL CONSTRAINTS
-- ========================================

-- Ensure route polyline is not empty
ALTER TABLE routes ADD CONSTRAINT check_route_polyline_not_empty 
    CHECK (route_polyline IS NOT NULL AND trim(route_polyline) != '');

-- Ensure planned ruck dates are not in the past (optional)
-- ALTER TABLE planned_ruck ADD CONSTRAINT check_planned_date_future 
--     CHECK (planned_date IS NULL OR planned_date >= NOW() - INTERVAL '1 day');

-- ========================================
-- 10. COMMENTS FOR DOCUMENTATION
-- ========================================

COMMENT ON TABLE routes IS 'Shareable route data for AllTrails integration and community features';
COMMENT ON TABLE route_elevation_point IS 'Detailed elevation profile data for routes';
COMMENT ON TABLE route_point_of_interest IS 'Points of interest along routes (water, rest stops, hazards, etc.)';
COMMENT ON TABLE planned_ruck IS 'User-specific planned ruck sessions linked to routes';
COMMENT ON TABLE route_analytics IS 'Analytics and user interactions with routes for popularity tracking';

COMMENT ON COLUMN routes.route_polyline IS 'Encoded polyline string or GeoJSON representing the route path';
COMMENT ON COLUMN routes.external_id IS 'ID from external source like AllTrails trail ID';
COMMENT ON COLUMN routes.source IS 'Source of the route: alltrails, custom, or community';
COMMENT ON COLUMN planned_ruck.estimated_duration_hours IS 'Estimated completion time based on user profile and route difficulty';

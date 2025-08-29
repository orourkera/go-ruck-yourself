-- Calorie Method Comparison SQL Queries for Supabase
-- Run these queries directly in your Supabase SQL editor

-- ==============================================================================
-- STEP 1: Create helper functions for calorie calculations
-- ==============================================================================

-- Function to calculate MET-based calories (current method)
CREATE OR REPLACE FUNCTION calculate_met_calories(
    user_weight_kg FLOAT,
    ruck_weight_kg FLOAT,
    distance_km FLOAT,
    elevation_gain_m FLOAT,
    duration_seconds INTEGER,
    elevation_loss_m FLOAT DEFAULT 0.0,
    gender TEXT DEFAULT NULL
) RETURNS FLOAT AS $$
DECLARE
    duration_hours FLOAT;
    avg_speed_kmh FLOAT;
    avg_speed_mph FLOAT;
    avg_grade FLOAT;
    ruck_weight_lbs FLOAT;
    base_met FLOAT;
    grade_adjustment FLOAT;
    load_adjustment FLOAT;
    final_met FLOAT;
    base_calories FLOAT;
    gender_adjusted_calories FLOAT;
BEGIN
    -- Calculate speed and grade
    IF duration_seconds > 0 THEN
        duration_hours := duration_seconds::FLOAT / 3600.0;
        avg_speed_kmh := distance_km / duration_hours;
    ELSE
        avg_speed_kmh := 5.0; -- fallback
        duration_hours := distance_km / 5.0;
    END IF;
    
    avg_speed_mph := avg_speed_kmh * 0.621371;
    
    IF distance_km > 0 THEN
        avg_grade := ((elevation_gain_m - elevation_loss_m) / (distance_km * 1000)) * 100;
    ELSE
        avg_grade := 0.0;
    END IF;
    
    ruck_weight_lbs := ruck_weight_kg * 2.20462;
    
    -- Base MET based on speed
    IF avg_speed_mph < 2.0 THEN
        base_met := 2.5;
    ELSIF avg_speed_mph < 2.5 THEN
        base_met := 3.0;
    ELSIF avg_speed_mph < 3.0 THEN
        base_met := 3.5;
    ELSIF avg_speed_mph < 3.5 THEN
        base_met := 4.0;
    ELSIF avg_speed_mph < 4.0 THEN
        base_met := 4.5;
    ELSIF avg_speed_mph < 5.0 THEN
        base_met := 5.0;
    ELSE
        base_met := 6.0;
    END IF;
    
    -- Grade adjustment
    IF avg_grade > 0 THEN
        grade_adjustment := avg_grade * 0.6 * (avg_speed_mph / 4.0);
    ELSIF avg_grade < 0 THEN
        IF ABS(avg_grade) <= 10 THEN
            grade_adjustment := -ABS(avg_grade) * 0.1;
        ELSE
            grade_adjustment := (ABS(avg_grade) - 10) * 0.15;
        END IF;
    ELSE
        grade_adjustment := 0.0;
    END IF;
    
    -- Load adjustment
    IF ruck_weight_lbs > 0 THEN
        load_adjustment := LEAST(ruck_weight_lbs * 0.05, 5.0);
    ELSE
        load_adjustment := 0.0;
    END IF;
    
    -- Final MET
    final_met := GREATEST(2.0, LEAST(base_met + grade_adjustment + load_adjustment, 15.0));
    
    -- Base calories
    base_calories := final_met * (user_weight_kg + ruck_weight_kg) * duration_hours;
    
    -- Gender adjustment
    IF gender = 'female' THEN
        gender_adjusted_calories := base_calories * 0.85;
    ELSIF gender = 'male' THEN
        gender_adjusted_calories := base_calories;
    ELSE
        gender_adjusted_calories := base_calories * 0.925;
    END IF;
    
    RETURN GREATEST(0, gender_adjusted_calories);
END;
$$ LANGUAGE plpgsql;

-- Function to calculate Mechanical calories (Pandolf method)
CREATE OR REPLACE FUNCTION calculate_mechanical_calories(
    user_weight_kg FLOAT,
    ruck_weight_kg FLOAT,
    distance_km FLOAT,
    elevation_gain_m FLOAT,
    duration_seconds INTEGER
) RETURNS FLOAT AS $$
DECLARE
    speed_kmh FLOAT;
    grade_pct FLOAT;
    v FLOAT; -- speed in m/s
    W FLOAT; -- user weight
    L FLOAT; -- ruck weight
    G FLOAT; -- grade
    lw FLOAT; -- load ratio
    term_load FLOAT;
    term_speed_grade FLOAT;
    M FLOAT; -- metabolic power in watts
    load_ratio FLOAT;
    speed_mph FLOAT;
    adjustment_factor FLOAT;
    base_adjustment FLOAT;
    speed_factor FLOAT;
    kcal_per_sec FLOAT;
    kcal FLOAT;
BEGIN
    -- Calculate speed and grade
    IF duration_seconds > 0 THEN
        speed_kmh := distance_km / (duration_seconds::FLOAT / 3600.0);
    ELSE
        speed_kmh := 5.0;
    END IF;
    
    IF distance_km > 0 THEN
        grade_pct := (elevation_gain_m / (distance_km * 1000)) * 100;
    ELSE
        grade_pct := 0.0;
    END IF;
    
    -- Convert units for Pandolf equation
    v := LEAST(3.0, speed_kmh / 3.6); -- m/s, capped at 3 m/s
    W := user_weight_kg;
    L := ruck_weight_kg;
    G := GREATEST(-20.0, LEAST(grade_pct, 30.0)); -- clamp grade
    
    -- Pandolf baseline equation
    IF W > 0 THEN
        lw := L / W;
    ELSE
        lw := 0.0;
    END IF;
    
    term_load := 2.0 * (W + L) * (lw * lw);
    term_speed_grade := (W + L) * (1.5 * v * v + 0.35 * v * G);
    M := 1.5 * W + term_load + term_speed_grade;
    
    -- GORUCK load ratio adjustment
    load_ratio := lw;
    speed_mph := speed_kmh * 0.621371;
    adjustment_factor := 1.0;
    
    IF load_ratio > 0 AND speed_mph > 2.0 THEN
        base_adjustment := LEAST(load_ratio * 0.45, 0.15); -- cap at 15%
        speed_factor := LEAST((speed_mph - 2.0) / 2.0, 1.0);
        adjustment_factor := 1.0 + (base_adjustment * speed_factor);
    END IF;
    
    M := M * adjustment_factor;
    M := GREATEST(50.0, LEAST(M, 800.0)); -- clamp to reasonable range
    
    -- Convert W→kcal
    kcal_per_sec := M / 4186.0;
    kcal := kcal_per_sec * duration_seconds;
    
    -- Handle very low speeds
    IF speed_kmh < 0.5 AND duration_seconds > 0 THEN
        kcal := kcal * 0.2;
    END IF;
    
    RETURN GREATEST(0, kcal);
END;
$$ LANGUAGE plpgsql;

-- Function to calculate Fusion calories (simplified - mechanical only for now)
CREATE OR REPLACE FUNCTION calculate_fusion_calories(
    user_weight_kg FLOAT,
    ruck_weight_kg FLOAT,
    distance_km FLOAT,
    elevation_gain_m FLOAT,
    duration_seconds INTEGER,
    gender TEXT DEFAULT NULL
) RETURNS FLOAT AS $$
DECLARE
    mechanical_cal FLOAT;
    fusion_cal FLOAT;
BEGIN
    -- Get mechanical calories
    mechanical_cal := calculate_mechanical_calories(
        user_weight_kg, ruck_weight_kg, distance_km, elevation_gain_m, duration_seconds
    );
    
    -- For now, fusion = mechanical (no HR data processing)
    fusion_cal := mechanical_cal;
    
    -- Weather adjustment (default = 1.0)
    fusion_cal := fusion_cal * 1.0;
    
    -- Cap within ±15% of mechanical
    fusion_cal := GREATEST(mechanical_cal * 0.85, LEAST(fusion_cal, mechanical_cal * 1.15));
    
    -- Gender adjustment if unknown
    IF gender IS NULL THEN
        fusion_cal := fusion_cal * 0.925;
    END IF;
    
    RETURN fusion_cal;
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- STEP 2: Main comparison query
-- ==============================================================================

WITH session_analysis AS (
  SELECT 
    rs.id as session_id,
    rs.distance_km,
    rs.duration_seconds,
    rs.duration_seconds::FLOAT / 3600.0 as duration_hours,
    CASE 
      WHEN rs.duration_seconds > 0 THEN rs.distance_km / (rs.duration_seconds::FLOAT / 3600.0)
      ELSE 0 
    END as speed_kmh,
    rs.elevation_gain_m,
    rs.elevation_loss_m,
    rs.calories_burned as actual_calories,
    rs.ruck_weight_kg,
    u.weight_kg as user_weight_kg,
    u.gender,
    rs.completed_at,
    
    -- Calculate calories using all three methods
    calculate_met_calories(
      u.weight_kg, 
      COALESCE(rs.ruck_weight_kg, 0.0), 
      rs.distance_km, 
      COALESCE(rs.elevation_gain_m, 0.0), 
      rs.duration_seconds,
      COALESCE(rs.elevation_loss_m, 0.0),
      u.gender
    ) as current_method_calories,
    
    calculate_mechanical_calories(
      u.weight_kg,
      COALESCE(rs.ruck_weight_kg, 0.0),
      rs.distance_km,
      COALESCE(rs.elevation_gain_m, 0.0),
      rs.duration_seconds
    ) as mechanical_method_calories,
    
    calculate_fusion_calories(
      u.weight_kg,
      COALESCE(rs.ruck_weight_kg, 0.0),
      rs.distance_km,
      COALESCE(rs.elevation_gain_m, 0.0),
      rs.duration_seconds,
      u.gender
    ) as fusion_method_calories,
    
    -- Count heart rate samples for reference
    (SELECT COUNT(*) FROM heart_rate_sample hrs WHERE hrs.session_id = rs.id) as hr_sample_count
    
  FROM ruck_session rs
  JOIN "user" u ON rs.user_id = u.id
  WHERE rs.status = 'completed'
    AND rs.distance_km >= 1.0
    AND rs.duration_seconds > 0
    AND rs.calories_burned > 0
    AND u.weight_kg > 0
  ORDER BY rs.completed_at DESC
  LIMIT 100
),

comparison_analysis AS (
  SELECT *,
    -- Calculate percentage differences vs actual stored calories
    CASE 
      WHEN actual_calories > 0 THEN ((current_method_calories - actual_calories) / actual_calories) * 100
      ELSE 0 
    END as current_vs_actual_pct,
    
    CASE 
      WHEN actual_calories > 0 THEN ((mechanical_method_calories - actual_calories) / actual_calories) * 100
      ELSE 0 
    END as mechanical_vs_actual_pct,
    
    CASE 
      WHEN actual_calories > 0 THEN ((fusion_method_calories - actual_calories) / actual_calories) * 100
      ELSE 0 
    END as fusion_vs_actual_pct,
    
    -- Calculate method comparisons
    CASE 
      WHEN current_method_calories > 0 THEN ((mechanical_method_calories - current_method_calories) / current_method_calories) * 100
      ELSE 0 
    END as mechanical_vs_current_pct,
    
    CASE 
      WHEN current_method_calories > 0 THEN ((fusion_method_calories - current_method_calories) / current_method_calories) * 100
      ELSE 0 
    END as fusion_vs_current_pct,
    
    CASE 
      WHEN mechanical_method_calories > 0 THEN ((fusion_method_calories - mechanical_method_calories) / mechanical_method_calories) * 100
      ELSE 0 
    END as fusion_vs_mechanical_pct
    
  FROM session_analysis
)

-- Main results
SELECT 
  session_id,
  distance_km,
  ROUND(duration_hours::NUMERIC, 2) as duration_hours,
  ROUND(speed_kmh::NUMERIC, 2) as speed_kmh,
  elevation_gain_m,
  ruck_weight_kg,
  user_weight_kg,
  gender,
  hr_sample_count > 0 as has_hr_data,
  
  -- Calorie values
  ROUND(actual_calories::NUMERIC, 0) as actual_calories,
  ROUND(current_method_calories::NUMERIC, 0) as current_method_calories,
  ROUND(mechanical_method_calories::NUMERIC, 0) as mechanical_method_calories,
  ROUND(fusion_method_calories::NUMERIC, 0) as fusion_method_calories,
  
  -- Percentage differences vs stored values
  ROUND(current_vs_actual_pct::NUMERIC, 1) as current_vs_actual_pct,
  ROUND(mechanical_vs_actual_pct::NUMERIC, 1) as mechanical_vs_actual_pct,
  ROUND(fusion_vs_actual_pct::NUMERIC, 1) as fusion_vs_actual_pct,
  
  -- Method comparisons
  ROUND(mechanical_vs_current_pct::NUMERIC, 1) as mechanical_vs_current_pct,
  ROUND(fusion_vs_current_pct::NUMERIC, 1) as fusion_vs_current_pct,
  ROUND(fusion_vs_mechanical_pct::NUMERIC, 1) as fusion_vs_mechanical_pct,
  
  completed_at

FROM comparison_analysis
ORDER BY completed_at DESC;

-- ==============================================================================
-- STEP 3: Summary statistics query
-- ==============================================================================

WITH session_analysis AS (
  SELECT 
    rs.id,
    rs.distance_km,
    rs.duration_seconds,
    rs.calories_burned as actual_calories,
    u.weight_kg as user_weight_kg,
    u.gender,
    30 as age, -- Default age since user table doesn't have age column
    COALESCE(rs.ruck_weight_kg, 0.0) as ruck_weight_kg,
    COALESCE(rs.elevation_gain_m, 0.0) as elevation_gain_m,
    COALESCE(rs.elevation_loss_m, 0.0) as elevation_loss_m,
    
    calculate_met_calories(
      u.weight_kg, COALESCE(rs.ruck_weight_kg, 0.0), rs.distance_km, 
      COALESCE(rs.elevation_gain_m, 0.0), rs.duration_seconds,
      COALESCE(rs.elevation_loss_m, 0.0), u.gender
    ) as current_method_calories,
    
    calculate_mechanical_calories(
      u.weight_kg, COALESCE(rs.ruck_weight_kg, 0.0), rs.distance_km,
      COALESCE(rs.elevation_gain_m, 0.0), rs.duration_seconds
    ) as mechanical_method_calories,
    
    calculate_fusion_calories(
      u.weight_kg, COALESCE(rs.ruck_weight_kg, 0.0), rs.distance_km,
      COALESCE(rs.elevation_gain_m, 0.0), rs.duration_seconds, u.gender
    ) as fusion_method_calories,
    
    (SELECT COUNT(*) FROM heart_rate_sample hrs WHERE hrs.session_id = rs.id) as hr_sample_count
    
  FROM ruck_session rs
  JOIN "user" u ON rs.user_id = u.id
  WHERE rs.status = 'completed'
    AND rs.distance_km >= 1.0
    AND rs.duration_seconds > 0
    AND rs.calories_burned > 0
    AND u.weight_kg > 0
  ORDER BY rs.completed_at DESC
  LIMIT 100
),

summary_stats AS (
  SELECT 
    COUNT(*) as total_sessions,
    COUNT(CASE WHEN hr_sample_count > 0 THEN 1 END) as sessions_with_hr,
    ROUND(AVG(distance_km)::NUMERIC, 2) as avg_distance_km,
    ROUND(AVG(duration_seconds::FLOAT / 3600.0)::NUMERIC, 2) as avg_duration_hours,
    ROUND(AVG(ruck_weight_kg)::NUMERIC, 2) as avg_ruck_weight_kg,
    
    -- Accuracy vs stored values (Mean Absolute Error)
    ROUND(AVG(ABS(((current_method_calories - actual_calories) / actual_calories) * 100))::NUMERIC, 1) as current_mae,
    ROUND(AVG(ABS(((mechanical_method_calories - actual_calories) / actual_calories) * 100))::NUMERIC, 1) as mechanical_mae,
    ROUND(AVG(ABS(((fusion_method_calories - actual_calories) / actual_calories) * 100))::NUMERIC, 1) as fusion_mae,
    
    -- Average differences vs stored values
    ROUND(AVG(((current_method_calories - actual_calories) / actual_calories) * 100)::NUMERIC, 1) as current_avg_diff,
    ROUND(AVG(((mechanical_method_calories - actual_calories) / actual_calories) * 100)::NUMERIC, 1) as mechanical_avg_diff,
    ROUND(AVG(((fusion_method_calories - actual_calories) / actual_calories) * 100)::NUMERIC, 1) as fusion_avg_diff,
    
    -- Method comparisons
    ROUND(AVG(((mechanical_method_calories - current_method_calories) / current_method_calories) * 100)::NUMERIC, 1) as mechanical_vs_current_avg,
    ROUND(AVG(((fusion_method_calories - current_method_calories) / current_method_calories) * 100)::NUMERIC, 1) as fusion_vs_current_avg,
    
    -- Count where new methods are higher than current
    COUNT(CASE WHEN mechanical_method_calories > current_method_calories THEN 1 END) as mechanical_higher_count,
    COUNT(CASE WHEN fusion_method_calories > current_method_calories THEN 1 END) as fusion_higher_count
    
  FROM session_analysis
)

SELECT 
  '📊 SUMMARY STATISTICS' as section,
  'Total sessions: ' || total_sessions as stat_1,
  'Sessions with HR data: ' || sessions_with_hr || ' (' || ROUND((sessions_with_hr::FLOAT / total_sessions * 100)::NUMERIC, 1) || '%)' as stat_2,
  'Average distance: ' || avg_distance_km || ' km' as stat_3,
  'Average duration: ' || avg_duration_hours || ' hours' as stat_4,
  'Average ruck weight: ' || avg_ruck_weight_kg || ' kg' as stat_5
FROM summary_stats

UNION ALL

SELECT 
  '🎯 ACCURACY vs STORED VALUES (Mean Absolute Error)' as section,
  'CURRENT Method: ' || current_mae || '%' as stat_1,
  'MECHANICAL Method: ' || mechanical_mae || '%' as stat_2,
  'FUSION Method: ' || fusion_mae || '%' as stat_3,
  '' as stat_4,
  '' as stat_5
FROM summary_stats

UNION ALL

SELECT 
  '⚖️ METHOD COMPARISONS' as section,
  'Mechanical vs Current: ' || mechanical_vs_current_avg || '% average difference' as stat_1,
  'Fusion vs Current: ' || fusion_vs_current_avg || '% average difference' as stat_2,
  'Sessions where Mechanical > Current: ' || mechanical_higher_count || ' (' || ROUND((mechanical_higher_count::FLOAT / total_sessions * 100)::NUMERIC, 1) || '%)' as stat_3,
  'Sessions where Fusion > Current: ' || fusion_higher_count || ' (' || ROUND((fusion_higher_count::FLOAT / total_sessions * 100)::NUMERIC, 1) || '%)' as stat_4,
  '' as stat_5
FROM summary_stats;

-- ==============================================================================
-- STEP 4: Clean up functions (run this after analysis if desired)
-- ==============================================================================

-- Uncomment these lines to remove the functions after analysis
-- DROP FUNCTION IF EXISTS calculate_met_calories(FLOAT, FLOAT, FLOAT, FLOAT, INTEGER, FLOAT, TEXT);
-- DROP FUNCTION IF EXISTS calculate_mechanical_calories(FLOAT, FLOAT, FLOAT, FLOAT, INTEGER);
-- DROP FUNCTION IF EXISTS calculate_fusion_calories(FLOAT, FLOAT, FLOAT, FLOAT, INTEGER, TEXT);

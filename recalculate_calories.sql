-- Recalculate calories for sessions 2525 and 2523 using the same Pandolf algorithm as Flutter app
-- This matches the MetCalculator._calculateMechanicalCaloriesPandolf() method (fusion fallback)

WITH session_data AS (
    -- Get current session data
    SELECT 
        id,
        user_id,
        weight_kg,
        ruck_weight_kg,
        distance_km,
        duration_seconds,
        elevation_gain_m,
        elevation_loss_m,
        calories_burned as current_calories
    FROM ruck_session 
    WHERE id IN (2525, 2523)
),
calculated_metrics AS (
    -- Calculate speed, grade, and MET values
    SELECT 
        sd.*,
        -- Calculate average speed (km/h)
        CASE 
            WHEN sd.duration_seconds > 0 THEN (sd.distance_km / (sd.duration_seconds / 3600.0))
            ELSE 0
        END as avg_speed_kmh,
        -- Convert to mph
        CASE 
            WHEN sd.duration_seconds > 0 THEN (sd.distance_km / (sd.duration_seconds / 3600.0)) * 0.621371
            ELSE 0
        END as avg_speed_mph,
        -- Calculate effective uphill grade (using only elevation gain, not net)
        CASE 
            WHEN sd.distance_km > 0 THEN (GREATEST(0, sd.elevation_gain_m) / (sd.distance_km * 1000)) * 100
            ELSE 0
        END as effective_grade_pct,
        -- Convert ruck weight to pounds
        sd.ruck_weight_kg * 2.20462 as ruck_weight_lbs
    FROM session_data sd
),
pandolf_calculations AS (
    -- Calculate Pandolf equation values using the same logic as Flutter
    SELECT 
        cm.*,
        -- Convert speed to m/s (clamped to 0-3 m/s for walking speeds)
        LEAST(GREATEST(cm.avg_speed_kmh / 3.6, 0.0), 3.0) as speed_ms,
        -- Calculate load-to-weight ratio (L/W)
        CASE 
            WHEN cm.weight_kg > 0 THEN cm.ruck_weight_kg / cm.weight_kg
            ELSE 0.0
        END as load_weight_ratio,
        -- Clamp grade to -20% to +30%
        LEAST(GREATEST(cm.effective_grade_pct, -20.0), 30.0) as clamped_grade_pct
    FROM calculated_metrics cm
),
mechanical_calculations AS (
    -- Calculate mechanical calories using Pandolf equation
    SELECT 
        pc.*,
        -- Pandolf (1977) baseline: M (W) = 1.5W + 2.0(W+L)(L/W)^2 + eta*(W+L)*(1.5 v^2 + 0.35 v G)
        -- Where: W = user weight, L = load weight, v = speed (m/s), G = grade (%), eta = terrain factor (1.0)
        (1.5 * pc.weight_kg) + 
        (2.0 * (pc.weight_kg + pc.ruck_weight_kg) * (pc.load_weight_ratio * pc.load_weight_ratio)) +
        (1.0 * (pc.weight_kg + pc.ruck_weight_kg) * (1.5 * pc.speed_ms * pc.speed_ms + 0.35 * pc.speed_ms * pc.clamped_grade_pct)) as pandolf_watts,
        -- Convert speed to mph for adjustment factor
        pc.avg_speed_mph as speed_mph
    FROM pandolf_calculations pc
),
adjusted_calculations AS (
    -- Apply GORUCK-inspired load ratio adjustment
    SELECT 
        mc.*,
        -- Calculate adjustment factor based on load ratio and speed
        CASE 
            WHEN mc.load_weight_ratio > 0 AND mc.speed_mph > 2.0 THEN
                -- Base adjustment scales with load ratio (0-15% at max, reduced from 27%)
                LEAST(mc.load_weight_ratio * 0.45, 0.15)
            ELSE
                0.0
        END as base_adjustment,
        CASE 
            WHEN mc.load_weight_ratio > 0 AND mc.speed_mph > 2.0 THEN
                -- Speed factor: more adjustment at higher speeds (0-1 factor for 2-4mph+)
                LEAST((mc.speed_mph - 2.0) / 2.0, 1.0)
            ELSE
                0.0
        END as speed_factor
    FROM mechanical_calculations mc
),
final_calculations AS (
    -- Calculate final adjusted calories
    SELECT 
        ac.id,
        ac.user_id,
        ac.weight_kg,
        ac.ruck_weight_kg,
        ac.distance_km,
        ac.duration_seconds,
        ac.elevation_gain_m,
        ac.elevation_loss_m,
        ac.avg_speed_kmh,
        ac.avg_speed_mph,
        ac.effective_grade_pct,
        ac.ruck_weight_lbs,
        ac.speed_ms,
        ac.load_weight_ratio,
        ac.pandolf_watts,
        ac.base_adjustment,
        ac.speed_factor,
        -- Apply the research-based adjustment factor
        CASE 
            WHEN ac.base_adjustment > 0 THEN
                ac.pandolf_watts * (1.0 + (ac.base_adjustment * ac.speed_factor))
            ELSE
                ac.pandolf_watts
        END as adjusted_watts,
        -- Convert watts to calories per second
        CASE 
            WHEN ac.base_adjustment > 0 THEN
                (ac.pandolf_watts * (1.0 + (ac.base_adjustment * ac.speed_factor))) / 4186.0
            ELSE
                ac.pandolf_watts / 4186.0
        END as calories_per_second,
        -- Get current calories from session data
        sd.current_calories
    FROM adjusted_calculations ac
    JOIN session_data sd ON ac.id = sd.id
)
-- Show the calculations and new calorie values
SELECT 
    id as session_id,
    user_id,
    weight_kg,
    ruck_weight_kg,
    distance_km,
    duration_seconds,
    ROUND((duration_seconds / 3600.0)::numeric, 2) as duration_hours,
    elevation_gain_m,
    elevation_loss_m,
    ROUND(avg_speed_kmh::numeric, 2) as avg_speed_kmh,
    ROUND(avg_speed_mph::numeric, 2) as avg_speed_mph,
    ROUND(effective_grade_pct::numeric, 1) as effective_grade_pct,
    ROUND(ruck_weight_lbs::numeric, 1) as ruck_weight_lbs,
    ROUND(speed_ms::numeric, 2) as speed_ms,
    ROUND(load_weight_ratio::numeric, 3) as load_weight_ratio,
    ROUND(pandolf_watts::numeric, 0) as pandolf_watts,
    ROUND(base_adjustment::numeric, 3) as base_adjustment,
    ROUND(speed_factor::numeric, 2) as speed_factor,
    ROUND(adjusted_watts::numeric, 0) as adjusted_watts,
    ROUND(calories_per_second::numeric, 3) as calories_per_second,
    current_calories,
    -- Calculate new calories: calories_per_second × duration_seconds
    ROUND((calories_per_second * duration_seconds)::numeric, 0) as new_calories,
    -- Show the difference
    ROUND(((calories_per_second * duration_seconds) - current_calories)::numeric, 0) as calorie_difference
FROM final_calculations
ORDER BY id;

-- Uncomment the UPDATE statement below to actually update the calories
/*
UPDATE ruck_session 
SET calories_burned = (
    SELECT ROUND(calculated_calories::numeric, 0)
    FROM (
        WITH session_data AS (
            SELECT 
                id,
                user_id,
                weight_kg,
                ruck_weight_kg,
                distance_km,
                duration_seconds,
                elevation_gain_m,
                elevation_loss_m,
                calories_burned as current_calories
            FROM ruck_session 
            WHERE id IN (2525, 2523)
        ),
        calculated_metrics AS (
            SELECT 
                sd.*,
                CASE 
                    WHEN sd.duration_seconds > 0 THEN (sd.distance_km / (sd.duration_seconds / 3600.0))
                    ELSE 0
                END as avg_speed_kmh,
                CASE 
                    WHEN sd.duration_seconds > 0 THEN (sd.distance_km / (sd.duration_seconds / 3600.0)) * 0.621371
                    ELSE 0
                END as avg_speed_mph,
                CASE 
                    WHEN sd.distance_km > 0 THEN (GREATEST(0, sd.elevation_gain_m) / (sd.distance_km * 1000)) * 100
                    ELSE 0
                END as effective_grade_pct,
                sd.ruck_weight_kg * 2.20462 as ruck_weight_lbs
            FROM session_data sd
        ),
        pandolf_calculations AS (
            SELECT 
                cm.*,
                LEAST(GREATEST(cm.avg_speed_kmh / 3.6, 0.0), 3.0) as speed_ms,
                CASE 
                    WHEN cm.weight_kg > 0 THEN cm.ruck_weight_kg / cm.weight_kg
                    ELSE 0.0
                END as load_weight_ratio,
                LEAST(GREATEST(cm.effective_grade_pct, -20.0), 30.0) as clamped_grade_pct
            FROM calculated_metrics cm
        ),
        mechanical_calculations AS (
            SELECT 
                pc.*,
                (1.5 * pc.weight_kg) + 
                (2.0 * (pc.weight_kg + pc.ruck_weight_kg) * (pc.load_weight_ratio * pc.load_weight_ratio)) +
                (1.0 * (pc.weight_kg + pc.ruck_weight_kg) * (1.5 * pc.speed_ms * pc.speed_ms + 0.35 * pc.speed_ms * pc.clamped_grade_pct)) as pandolf_watts,
                pc.avg_speed_mph as speed_mph
            FROM pandolf_calculations pc
        ),
        adjusted_calculations AS (
            SELECT 
                mc.*,
                CASE 
                    WHEN mc.load_weight_ratio > 0 AND mc.speed_mph > 2.0 THEN
                        LEAST(mc.load_weight_ratio * 0.45, 0.15)
                    ELSE
                        0.0
                END as base_adjustment,
                CASE 
                    WHEN mc.load_weight_ratio > 0 AND mc.speed_mph > 2.0 THEN
                        LEAST((mc.speed_mph - 2.0) / 2.0, 1.0)
                    ELSE
                        0.0
                END as speed_factor
            FROM mechanical_calculations mc
        ),
        final_calculations AS (
            SELECT 
                ac.id,
                ac.duration_seconds,
                CASE 
                    WHEN ac.base_adjustment > 0 THEN
                        (ac.pandolf_watts * (1.0 + (ac.base_adjustment * ac.speed_factor))) / 4186.0
                    ELSE
                        ac.pandolf_watts / 4186.0
                END as calories_per_second
            FROM adjusted_calculations ac
        )
        SELECT (calories_per_second * duration_seconds) as calculated_calories
        FROM final_calculations 
        WHERE final_calculations.id = ruck_session.id
    ) calc
)
WHERE id IN (2525, 2523);
*/

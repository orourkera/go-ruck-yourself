-- Quick Start Sprint achievement
INSERT INTO achievements (
    achievement_key,
    name,
    description,
    category,
    tier,
    criteria,
    icon_name,
    is_active,
    unit_preference,
    created_at,
    updated_at
)
VALUES (
    'quick_start_3in7',
    'Quick Start Sprint',
    'Complete 3 qualifying rucks in any 7-day window.',
    'consistency',
    'bronze',
    jsonb_build_object(
        'type', 'sessions_in_window',
        'target', 3,
        'window_days', 7,
        'min_duration_s', 300,
        'min_distance_km', 0.5
    ),
    'streak',
    TRUE,
    NULL,
    NOW(),
    NOW()
)
ON CONFLICT (achievement_key) DO UPDATE
SET
    name            = EXCLUDED.name,
    description     = EXCLUDED.description,
    category        = EXCLUDED.category,
    tier            = EXCLUDED.tier,
    criteria        = EXCLUDED.criteria,
    icon_name       = EXCLUDED.icon_name,
    is_active       = EXCLUDED.is_active,
    unit_preference = EXCLUDED.unit_preference,
    updated_at      = NOW();

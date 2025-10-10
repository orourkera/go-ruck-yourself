-- Calculate MAU CAGR Month-over-Month since May
-- CAGR = (Ending Value / Beginning Value) ^ (1 / Number of Periods) - 1

WITH monthly_active_users AS (
    -- Calculate MAU for each month
    SELECT
        DATE_TRUNC('month', last_active_at) as month,
        COUNT(DISTINCT id) as mau
    FROM "user"
    WHERE last_active_at >= '2024-05-01'
        AND last_active_at IS NOT NULL
    GROUP BY DATE_TRUNC('month', last_active_at)
),
mau_with_growth AS (
    -- Calculate month-over-month growth
    SELECT
        month,
        mau,
        LAG(mau) OVER (ORDER BY month) as previous_mau,
        CASE
            WHEN LAG(mau) OVER (ORDER BY month) IS NOT NULL
            THEN ((mau::float / LAG(mau) OVER (ORDER BY month)) - 1) * 100
            ELSE NULL
        END as mom_growth_pct
    FROM monthly_active_users
),
cagr_calculation AS (
    -- Calculate CAGR from May to most recent complete month
    SELECT
        MIN(month) as start_month,
        MAX(month) as end_month,
        MIN(mau) FILTER (WHERE month = (SELECT MIN(month) FROM monthly_active_users)) as starting_mau,
        MAX(mau) FILTER (WHERE month = (SELECT MAX(month) FROM monthly_active_users)) as ending_mau,
        COUNT(*) - 1 as months_elapsed,
        -- CAGR formula: ((Ending/Beginning)^(1/periods) - 1) * 100
        CASE
            WHEN MIN(mau) FILTER (WHERE month = (SELECT MIN(month) FROM monthly_active_users)) > 0
            THEN (
                POWER(
                    MAX(mau) FILTER (WHERE month = (SELECT MAX(month) FROM monthly_active_users))::float /
                    MIN(mau) FILTER (WHERE month = (SELECT MIN(month) FROM monthly_active_users))::float,
                    1.0 / NULLIF(COUNT(*) - 1, 0)
                ) - 1
            ) * 100
            ELSE NULL
        END as cagr_pct
    FROM mau_with_growth
    WHERE mau IS NOT NULL
)
-- Final output with both monthly details and overall CAGR
SELECT
    'Monthly MAU Growth' as metric_type,
    TO_CHAR(m.month, 'YYYY-MM') as month,
    m.mau,
    m.previous_mau,
    ROUND(m.mom_growth_pct, 2) as mom_growth_pct,
    NULL as overall_cagr
FROM mau_with_growth m
WHERE m.month >= '2024-05-01'

UNION ALL

SELECT
    'Overall CAGR' as metric_type,
    'May to ' || TO_CHAR(end_month, 'Mon') as month,
    ending_mau as mau,
    starting_mau as previous_mau,
    NULL as mom_growth_pct,
    ROUND(cagr_pct, 2) as overall_cagr
FROM cagr_calculation

ORDER BY
    CASE WHEN metric_type = 'Monthly MAU Growth' THEN 0 ELSE 1 END,
    month;

-- Alternative: Just the CAGR summary
/*
WITH monthly_active_users AS (
    SELECT
        DATE_TRUNC('month', last_active_at) as month,
        COUNT(DISTINCT id) as mau
    FROM "user"
    WHERE last_active_at >= '2024-05-01'
        AND last_active_at IS NOT NULL
    GROUP BY DATE_TRUNC('month', last_active_at)
)
SELECT
    MIN(month) as period_start,
    MAX(month) as period_end,
    MIN(mau) FILTER (WHERE month = (SELECT MIN(month) FROM monthly_active_users)) as starting_mau,
    MAX(mau) FILTER (WHERE month = (SELECT MAX(month) FROM monthly_active_users)) as ending_mau,
    COUNT(DISTINCT month) as months_count,
    ROUND(
        (POWER(
            MAX(mau) FILTER (WHERE month = (SELECT MAX(month) FROM monthly_active_users))::float /
            MIN(mau) FILTER (WHERE month = (SELECT MIN(month) FROM monthly_active_users))::float,
            1.0 / (COUNT(DISTINCT month) - 1)
        ) - 1) * 100,
        2
    ) as cagr_pct,
    ROUND(
        AVG(
            ((mau::float / LAG(mau) OVER (ORDER BY month)) - 1) * 100
        ),
        2
    ) as avg_mom_growth_pct
FROM monthly_active_users
WHERE mau IS NOT NULL;
*/
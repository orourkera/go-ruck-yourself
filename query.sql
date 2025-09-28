
WITH monthly_mau AS (
  SELECT
      DATE_TRUNC('month', completed_at)::date AS month_start,
      COUNT(DISTINCT user_id)                AS mau
  FROM ruck_session
  WHERE status = 'completed'
  GROUP BY DATE_TRUNC('month', completed_at)
),
bounds AS (
  SELECT
      MIN(month_start) AS first_month,
      MAX(month_start) AS last_month,
      MIN(mau)          AS first_mau,
      MAX(mau)          AS last_mau,
      COUNT(*)          AS months_count
  FROM monthly_mau
)
SELECT
    first_month,
    last_month,
    first_mau,
    last_mau,
    months_count,
    CASE
      WHEN first_mau = 0 OR months_count <= 1 THEN NULL
      ELSE POWER(last_mau::numeric / first_mau, 1.0 / (months_count - 1)) - 1
    END AS cagr_month_over_month
FROM bounds;

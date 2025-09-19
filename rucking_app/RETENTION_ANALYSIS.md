# Rucking App Retention Analysis

## Executive Summary

Based on user behavior analysis, we've identified two critical metrics for user retention:
1. **Week 1 Activation**: Users need **4+ sessions in their first week** (71%+ retention rate)
2. **Habit Formation**: Users who complete **7 total sessions** show 92.3% return rate (habit formed)

Currently, only 30% of users achieve the Week 1 activation threshold, representing our biggest opportunity for improvement.

---

## SQL Queries for Analysis

### 1. Cohort Retention Analysis (Weekly)
```sql
WITH cohorts AS (
  SELECT
    id AS user_id,
    DATE_TRUNC('week', created_at) AS cohort_week,
    TO_CHAR(DATE_TRUNC('week', created_at), 'YYYY-WW') AS cohort_week_label
  FROM public."user"
  WHERE created_at >= NOW() - INTERVAL '12 weeks'
),
weekly_activity AS (
  SELECT
    user_id,
    DATE_TRUNC('week', started_at) AS activity_week
  FROM public.ruck_session
  WHERE started_at >= NOW() - INTERVAL '12 weeks'
    AND status = 'completed'
  GROUP BY user_id, DATE_TRUNC('week', started_at)
),
cohort_retention AS (
  SELECT
    c.cohort_week,
    c.cohort_week_label,
    c.user_id,
    FLOOR(EXTRACT(EPOCH FROM (wa.activity_week - c.cohort_week)) / (7 * 86400)) AS weeks_since_signup
  FROM cohorts c
  LEFT JOIN weekly_activity wa ON c.user_id = wa.user_id
  WHERE wa.activity_week >= c.cohort_week
),
cohort_sizes AS (
  SELECT
    cohort_week,
    cohort_week_label,
    COUNT(DISTINCT user_id) AS cohort_size
  FROM cohorts
  GROUP BY cohort_week, cohort_week_label
)
SELECT
  cs.cohort_week_label AS "Week",
  cs.cohort_size AS "New Users",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 0 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 0",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 1 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 1",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 2 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 2",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 3 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 3",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 4 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 4",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 5 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 5",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 6 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 6",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 7 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 7",
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN weeks_since_signup = 8 THEN cr.user_id END) / cs.cohort_size, 1) AS "Week 8"
FROM cohort_retention cr
JOIN cohort_sizes cs ON cr.cohort_week = cs.cohort_week AND cr.cohort_week_label = cs.cohort_week_label
GROUP BY cs.cohort_week_label, cs.cohort_size, cr.cohort_week
ORDER BY cr.cohort_week ASC;
```

### 2. Magic Number Analysis (Session-Based Retention)
```sql
WITH user_sessions AS (
  SELECT
    user_id,
    COUNT(*) as total_sessions,
    MIN(started_at) as first_session,
    MAX(started_at) as last_session,
    EXTRACT(DAY FROM MAX(started_at) - MIN(started_at)) as days_active
  FROM public.ruck_session
  WHERE status = 'completed'
  GROUP BY user_id
),
session_counts AS (
  SELECT
    rs.user_id,
    ROW_NUMBER() OVER (PARTITION BY rs.user_id ORDER BY rs.started_at) as session_number,
    rs.started_at,
    LEAD(rs.started_at) OVER (PARTITION BY rs.user_id ORDER BY rs.started_at) as next_session,
    EXTRACT(DAY FROM LEAD(rs.started_at) OVER (PARTITION BY rs.user_id ORDER BY rs.started_at) - rs.started_at) as days_to_next
  FROM public.ruck_session rs
  WHERE status = 'completed'
),
retention_by_session_count AS (
  SELECT
    session_number,
    COUNT(DISTINCT user_id) as users_at_n_sessions,
    COUNT(DISTINCT CASE WHEN days_to_next <= 14 THEN user_id END) as users_returned_within_14d,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN days_to_next <= 14 THEN user_id END) / COUNT(DISTINCT user_id), 1) as return_rate
  FROM session_counts
  WHERE session_number <= 10
  GROUP BY session_number
)
SELECT * FROM retention_by_session_count
ORDER BY session_number;
```

### 3. First Week Behavior Analysis
```sql
WITH user_first_week AS (
  SELECT
    user_id,
    DATE_TRUNC('week', MIN(started_at)) as first_week,
    COUNT(*) as sessions_in_first_week
  FROM public.ruck_session
  WHERE status = 'completed'
  GROUP BY user_id
),
user_retention AS (
  SELECT
    fw.user_id,
    fw.sessions_in_first_week,
    COUNT(DISTINCT DATE_TRUNC('week', rs.started_at)) as total_weeks_active,
    MAX(rs.started_at) as last_activity,
    CASE
      WHEN MAX(rs.started_at) > NOW() - INTERVAL '30 days' THEN 'Active'
      WHEN MAX(rs.started_at) > NOW() - INTERVAL '90 days' THEN 'At Risk'
      ELSE 'Churned'
    END as user_status
  FROM user_first_week fw
  JOIN public.ruck_session rs ON fw.user_id = rs.user_id
  WHERE rs.status = 'completed'
  GROUP BY fw.user_id, fw.sessions_in_first_week
)
SELECT
  sessions_in_first_week,
  COUNT(*) as total_users,
  COUNT(CASE WHEN user_status = 'Active' THEN 1 END) as active_users,
  ROUND(100.0 * COUNT(CASE WHEN user_status = 'Active' THEN 1 END) / COUNT(*), 1) as active_rate
FROM user_retention
GROUP BY sessions_in_first_week
ORDER BY sessions_in_first_week;
```

### 4. Engagement Cliff Analysis
```sql
WITH user_journey AS (
  SELECT
    u.id as user_id,
    u.created_at,
    COUNT(DISTINCT DATE_TRUNC('day', rs.started_at)) as days_with_sessions,
    COUNT(rs.id) as total_sessions,
    MAX(rs.started_at) as last_session,
    EXTRACT(DAY FROM MAX(rs.started_at) - u.created_at) as days_from_signup_to_last
  FROM public."user" u
  LEFT JOIN public.ruck_session rs ON u.id = rs.user_id AND rs.status = 'completed'
  GROUP BY u.id, u.created_at
),
segmented AS (
  SELECT
    CASE
      WHEN total_sessions = 0 THEN '0: Never Started'
      WHEN total_sessions = 1 THEN '1: One and Done'
      WHEN total_sessions BETWEEN 2 AND 3 THEN '2-3: Tried It'
      WHEN total_sessions BETWEEN 4 AND 7 THEN '4-7: Exploring'
      WHEN total_sessions BETWEEN 8 AND 15 THEN '8-15: Building Habit'
      WHEN total_sessions > 15 THEN '16+: Habituated'
    END as user_segment,
    COUNT(*) as users,
    AVG(days_from_signup_to_last) as avg_days_active,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_from_signup_to_last) as median_days_active
  FROM user_journey
  GROUP BY user_segment
)
SELECT * FROM segmented
ORDER BY
  CASE user_segment
    WHEN '0: Never Started' THEN 0
    WHEN '1: One and Done' THEN 1
    WHEN '2-3: Tried It' THEN 2
    WHEN '4-7: Exploring' THEN 3
    WHEN '8-15: Building Habit' THEN 4
    WHEN '16+: Habituated' THEN 5
  END;
```

### 5. Time to Habit Formation
```sql
WITH user_weekly_sessions AS (
  SELECT
    user_id,
    DATE_TRUNC('week', started_at) as week,
    COUNT(*) as sessions_this_week
  FROM public.ruck_session
  WHERE status = 'completed'
  GROUP BY user_id, DATE_TRUNC('week', started_at)
),
user_patterns AS (
  SELECT
    user_id,
    week,
    sessions_this_week,
    AVG(sessions_this_week) OVER (
      PARTITION BY user_id
      ORDER BY week
      ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) as rolling_4w_avg,
    STDDEV(sessions_this_week) OVER (
      PARTITION BY user_id
      ORDER BY week
      ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) as rolling_4w_stddev
  FROM user_weekly_sessions
),
habit_formation AS (
  SELECT
    user_id,
    MIN(week) as first_consistent_week,
    EXTRACT(WEEK FROM MIN(week) - MIN(MIN(week)) OVER (PARTITION BY user_id)) as weeks_to_consistency
  FROM user_patterns
  WHERE rolling_4w_avg >= 2  -- At least 2 sessions per week average
    AND rolling_4w_stddev < 1  -- Low variance (consistent behavior)
  GROUP BY user_id
)
SELECT
  weeks_to_consistency,
  COUNT(*) as users,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM habit_formation
WHERE weeks_to_consistency IS NOT NULL
GROUP BY weeks_to_consistency
ORDER BY weeks_to_consistency;
```

---

## Key Findings

### Finding 1: The Magic Number is 7 Sessions
**Data from Magic Number Analysis:**

| Session # | Users | Return Rate |
|-----------|-------|-------------|
| 1 | 280 | 52.1% |
| 2 | 162 | 67.9% |
| 3 | 123 | 70.7% |
| 4 | 93 | 69.9% |
| 5 | 72 | 65.3% |
| 6 | 51 | 72.5% |
| **7** | **39** | **92.3%** ⬆️ |
| 8 | 36 | 83.3% |
| 9 | 30 | 96.7% |
| 10 | 29 | 86.2% |

**Insight**: Users who complete 7 sessions show a dramatic jump in retention (92.3%), indicating habit formation.

### Finding 2: First Week Activation Threshold is 4 Sessions
**Data from First Week Behavior Analysis:**

| First Week Sessions | Total Users | Active Users | Active Rate |
|--------------------|-------------|--------------|-------------|
| 1 | 118 | 50 | 42.4% |
| 2 | 39 | 24 | 61.5% |
| 3 | 30 | 15 | 50.0% |
| **4** | **21** | **15** | **71.4%** ⬆️ |
| 5 | 21 | 15 | 71.4% |
| 6 | 12 | 10 | 83.3% |
| 8+ | Various | High | 100% |

**Insight**: Users with 4+ sessions in their first week have 71%+ retention rates.

### Finding 3: User Drop-off Pattern

- **280 users** tried the app at least once
- **162 users (58%)** returned for session 2
- **39 users (14%)** reached session 7 (habit formation)
- Only **30% of users** achieve 4+ sessions in first week

---

## Strategic Recommendations

### 1. Immediate Actions (Quick Wins)

#### A. Fix Session 1→2 Conversion (Current: 52.1%)
- **Day 0**: Send "Great first ruck!" celebration push notification
- **Day 1**: "Your body is ready for session 2" reminder
- **Day 2**: If no session 2, send "Don't lose momentum" message
- Show progress bar: "1 of 4 sessions to build your habit"

#### B. Create "First Week Sprint" Campaign
- Goal: 4 sessions in 7 days
- Visual progress tracker on home screen
- Daily push notifications for first 7 days
- Special badge/achievement at 4 sessions

### 2. Medium-Term Initiatives

#### A. "Road to 7" Habit Program
- Create a structured 2-week program to reach 7 sessions
- Session milestones:
  - Session 3: "You're building consistency!"
  - Session 5: "Halfway to habit formation"
  - Session 7: "Habit Unlocked!" + special badge
- Unlock features progressively (social features at 5, coaching at 7)

#### B. Segmented User Journeys
Based on first week performance:
- **Low engagement (1-2 sessions)**: Recovery campaign with coaching
- **Medium engagement (3-4 sessions)**: Motivation to reach 7
- **High engagement (5+ sessions)**: Fast-track to premium features

### 3. Long-Term Strategy

#### A. Predictive Churn Prevention
- Flag users who haven't done session 2 within 48 hours
- Alert when users break their pattern (e.g., usually 3x/week, now 0)
- Automated re-engagement based on user segment

#### B. Social Accountability Features
- Introduce after session 3 (when users show commitment)
- Partner/buddy system to maintain accountability
- Group challenges starting at week 2

---

## Success Metrics to Track

### Primary KPIs
1. **Session 1→2 Conversion Rate** (Target: >70%, Current: 52.1%)
2. **Week 1: 4+ Sessions Rate** (Target: >50%, Current: 30%)
3. **Session 7 Achievement Rate** (Target: >25%, Current: 14%)

### Secondary KPIs
- Average sessions in first week
- Days to session 7
- 30-day retention by first-week cohort
- Return rate after session 7

### Cohort Tracking
- Weekly cohort retention curves
- First-week behavior → 30/60/90 day retention correlation
- Power user identification (8+ sessions in week 1)

---

## Implementation Priority

1. **Week 1**: Implement first-week push notification sequence
2. **Week 2**: Add progress tracking UI for "First Week Sprint"
3. **Week 3**: Launch "Road to 7" program with milestones
4. **Week 4**: Implement predictive churn alerts
5. **Month 2**: Roll out social features for committed users

---

## Additional Analysis Opportunities

1. **Time patterns**: What time of day/week do successful users ruck?
2. **Session characteristics**: Do longer/heavier first sessions predict retention?
3. **User demographics**: Age/location/fitness level correlation with retention
4. **Feature usage**: Which app features correlate with reaching session 7?
5. **Seasonal patterns**: How does retention vary by signup month?

---

*Analysis Date: 2025-09-19*
*Total Users Analyzed: 280*
*Key Finding: 7 sessions = habit formation, 4 first-week sessions = activation*
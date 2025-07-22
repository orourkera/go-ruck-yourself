# Ruck App Load Testing Guide

## Quick Start

### 1. Get a Bearer Token
```bash
node get-bearer-token.js
# Follow the prompts to enter your email/password
```

This will generate a `.env.loadtest` file with your token.

### 2. Run a Quick Test (2 minutes)
```bash
# Load the token into environment
source .env.loadtest

# Run quick test
artillery run quick-load-test.yml
```

### 3. Run Full Load Test (9 minutes)
```bash
# Load the token into environment  
source .env.loadtest

# Run comprehensive test
artillery run load-test-ruck.yml
```

### 4. Test Active Session Workflow (NEW!)
```bash
# Test complete ruck session journey: start → GPS tracking → completion
source .env.loadtest
artillery run load-test-active-sessions.yml
```

### 5. Quick Active Session Test (3 minutes)
```bash
# Quick test of session creation, location posting, and completion
source .env.loadtest  
artillery run quick-active-session-test.yml
```

### 6. Database Stress Test (3 minutes)
```bash
# Test heavy database writes (location_point inserts)
source .env.loadtest
artillery run load-test-database-stress.yml
```

## Test Scenarios Explained

### Quick Test (`quick-load-test.yml`)
- **Duration**: 2 minutes
- **Load**: 5-15 concurrent users
- **Purpose**: Quick performance check

### Full Test (`load-test-ruck.yml`)
- **Duration**: 9 minutes total
- **Load**: 2-20 concurrent users (gradual ramp)
- **Scenarios**:
  - **Typical User** (60%): Monthly stats → Recent rucks → Leaderboard
  - **Power User** (25%): All stats → Many rucks → Detailed views
  - **Social User** (15%): Leaderboard focus → User profiles

### Active Session Test (`load-test-active-sessions.yml`)
- **Duration**: 11 minutes total
- **Load**: 1-6 concurrent active ruckers
- **Database Impact**: **HIGH** (tests write performance)
- **Scenarios**:
  - **Complete Ruck Journey** (70%): Start → 20-30 location batches → Complete
  - **Quick Session** (20%): Start → 5-10 location points → Complete  
  - **GPS Heavy** (10%): Start → 40 high-frequency location batches → Complete

### Database Stress Test (`load-test-database-stress.yml`)
- **Duration**: 3 minutes
- **Load**: 5-10 concurrent users
- **Purpose**: **Test database write limits** (location_point inserts)
- **Scenarios**:
  - **High-Frequency Writes** (80%): Very frequent location posts (2-5 seconds)
  - **Batch Insert Test** (20%): Large batches of location points

## Understanding Results

### Good Performance Targets
```
Response Time:
  p50: < 200ms    (median)
  p95: < 500ms    (95th percentile)  
  p99: < 1000ms   (99th percentile)

Success Rate: > 99%
Error Rate: < 1%
```

### Sample Good Output
```
All virtual users finished
Summary report @ 10:06:42(+0200)

Scenarios launched:  450
Scenarios completed: 450
Requests completed:  1800
Mean response/sec:   5.2
Response time (msec):
  min: 45
  max: 892
  median: 124.5
  p95: 445.2
  p99: 598.1

Scenario counts:
  Typical User Journey: 270 (60%)
  Power User Journey: 113 (25%)
  Social User Journey: 67 (15%)

Codes:
  200: 1800 ✅ All requests successful
```

### Warning Signs
- **p95 > 1000ms**: Performance issues under load
- **Error rate > 5%**: Serious stability problems
- **Timeouts**: Server overwhelmed

## Advanced Testing

### Test Specific Endpoints
```bash
# Test just the stats endpoint
artillery quick --duration 60 --rate 10 --output stats-test.json https://getrucky.com/api/stats/monthly

# Test rucks endpoint (heavy load)
artillery quick --duration 60 --rate 5 --output rucks-test.json https://getrucky.com/api/rucks?limit=20
```

### Monitor During Tests
```bash
# Watch Heroku logs in another terminal
heroku logs --tail --app go-ruck-yourself

# Watch specific patterns
heroku logs --tail --app go-ruck-yourself | grep -E "(ERROR|took|ms)"
```

### Generate Reports
```bash
# Run test with detailed output
artillery run --output loadtest-results.json load-test-ruck.yml

# Generate HTML report
artillery report loadtest-results.json
```

## Scaling Insights

Based on your current setup:

- **Safe Load**: 50-100 concurrent users
- **Breaking Point**: Likely 200-500 concurrent users  
- **Bottlenecks**: Database queries, route processing

### When to Scale
- **Response times > 500ms** consistently
- **Error rate > 1%** during normal load
- **CPU utilization > 80%** on Heroku dyno

## Token Management

The bearer token expires, so for long tests:

```bash
# Check if token is still valid
curl -H "Authorization: Bearer $BEARER_TOKEN" https://getrucky.com/api/stats/monthly

# Get fresh token if needed
node get-bearer-token.js
source .env.loadtest
```

## Troubleshooting

### Common Issues

1. **401 Unauthorized**: Token expired or invalid
   ```bash
   node get-bearer-token.js  # Get fresh token
   ```

2. **Rate Limiting**: Too many requests
   ```bash
   # Reduce load in test config
   arrivalRate: 2  # Lower this number
   ```

3. **Connection Errors**: Network or server issues
   ```bash
   # Check server status
   curl https://getrucky.com/api/stats/monthly
   ```

Happy load testing! 🚀

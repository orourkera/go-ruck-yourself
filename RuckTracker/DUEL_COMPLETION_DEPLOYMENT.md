# Duel Completion Deployment Guide

## Overview
The duel completion system has been implemented with two deployment options for Heroku:

1. **Heroku Scheduler** (Recommended - Free)
2. **Background Worker Dyno** (More reliable - Paid)

## Option 1: Heroku Scheduler (FREE) ✅

### Step 1: Add Heroku Scheduler Add-on
```bash
heroku addons:create scheduler:standard --app your-app-name
```

### Step 2: Set Environment Variables
```bash
# Set your app URL for the scheduler script
heroku config:set HEROKU_APP_URL=https://your-app-name.herokuapp.com --app your-app-name

# Alternative: Set app name (script will construct URL)
heroku config:set HEROKU_APP_NAME=your-app-name --app your-app-name
```

### Step 3: Deploy Updated Code
```bash
git add .
git commit -m "Add duel completion system"
git push heroku main
```

### Step 4: Configure Scheduler Job
```bash
# Open Heroku Scheduler dashboard
heroku addons:open scheduler --app your-app-name

# Add new job with:
# - Command: python check_duel_completion.py
# - Frequency: Every 10 minutes
```

### Step 5: Test the Scheduler
```bash
# Run the job manually to test
heroku run python check_duel_completion.py --app your-app-name
```

## Option 2: Background Worker Dyno (PAID) ⚡

### Step 1: Deploy Updated Code
```bash
git add .
git commit -m "Add duel completion system with background worker"
git push heroku main
```

### Step 2: Scale Worker Dyno
```bash
# Scale up worker dyno (this will cost money)
heroku ps:scale worker=1 --app your-app-name
```

### Step 3: Set Environment Variables
```bash
heroku config:set HEROKU_APP_URL=https://your-app-name.herokuapp.com --app your-app-name
```

### Step 4: Monitor Worker
```bash
# Check worker status
heroku ps --app your-app-name

# View worker logs
heroku logs --tail --ps worker --app your-app-name
```

## Files Updated

### Backend API Files:
- ✅ `api/duels.py` - Added DuelCompletionCheckResource
- ✅ `api/duel_participants.py` - Enabled completion notifications
- ✅ `app.py` - Registered new completion endpoint

### Scheduler Files:
- ✅ `check_duel_completion.py` - Heroku Scheduler script
- ✅ `background_scheduler.py` - Background worker script
- ✅ `dependencies.txt` - Added APScheduler dependency
- ✅ `Procfile` - Added worker process

### Frontend Files:
- ✅ `lib/core/services/duel_completion_service.dart` - Flutter service
- ✅ `lib/core/services/service_locator.dart` - Service registration
- ✅ `lib/main.dart` - Auto-start service

## Monitoring & Debugging

### Check Logs
```bash
# Web dyno logs (API endpoint calls)
heroku logs --tail --app your-app-name

# Worker dyno logs (if using Option 2)
heroku logs --tail --ps worker --app your-app-name

# Scheduler logs (if using Option 1)
heroku logs --tail --app your-app-name | grep "check_duel_completion"
```

### Manual Testing
```bash
# Test the completion endpoint manually
curl -X POST https://your-app-name.herokuapp.com/api/duels/completion-check

# Or via Heroku CLI
heroku run python check_duel_completion.py --app your-app-name
```

### View Scheduler Jobs (Option 1)
```bash
# Open scheduler dashboard
heroku addons:open scheduler --app your-app-name
```

## Expected Behavior

### When Duels Expire:
1. **Scheduler/Worker** calls `/api/duels/completion-check` every 5-10 minutes
2. **Backend** finds expired active duels
3. **Backend** determines winners based on progress
4. **Backend** updates duel status to 'completed'
5. **Backend** sends push notifications to all participants
6. **Frontend** receives notifications via push/in-app system

### Completion Scenarios:
- 🏆 **Target Reached**: Someone reaches target → immediate winner
- ⏰ **Time Expired + Winner**: Clear winner based on progress
- 🤝 **Time Expired + Tie**: Multiple participants tied
- 😞 **Time Expired + No Progress**: "No one completed it. In this Duel there are no winners."

## Cost Comparison

### Option 1: Heroku Scheduler
- **Cost**: FREE (up to 100 jobs/month)
- **Reliability**: Good (runs every 10 minutes)
- **Limitations**: Jobs can timeout after 10 minutes

### Option 2: Background Worker
- **Cost**: ~$25/month (Standard dyno)
- **Reliability**: Excellent (always running)
- **Benefits**: More frequent checks (every 5 minutes), better monitoring

## Recommendation

Start with **Option 1 (Heroku Scheduler)** for the FREE tier, then upgrade to **Option 2 (Background Worker)** if you need more reliability or faster completion times.

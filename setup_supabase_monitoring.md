# Supabase Monitoring & Alerting Setup

## 1. Supabase Dashboard Alerts

### Navigate to Settings → Monitoring
- Set up alert rules for:
  - API errors (500, 400 status codes)
  - Database query failures
  - Auth signup/login failures
  - High latency (>1000ms)
  - Connection pool exhaustion

### Configure Notification Channels
- **Email**: Add your email for immediate alerts
- **Slack**: Create webhook URL and add to notifications
- **Discord**: Set up Discord webhook for team notifications

## 2. Database Function Monitoring

Create a monitoring function to track errors:

```sql
-- Create error logging table
CREATE TABLE IF NOT EXISTS public.error_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    error_type TEXT NOT NULL,
    error_message TEXT NOT NULL,
    user_id UUID,
    endpoint TEXT,
    request_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create monitoring function
CREATE OR REPLACE FUNCTION public.log_error(
    p_error_type TEXT,
    p_error_message TEXT,
    p_user_id UUID DEFAULT NULL,
    p_endpoint TEXT DEFAULT NULL,
    p_request_data JSONB DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    INSERT INTO public.error_logs (error_type, error_message, user_id, endpoint, request_data)
    VALUES (p_error_type, p_error_message, p_user_id, p_endpoint, p_request_data);
END;
$$ LANGUAGE plpgsql;

-- Create alert trigger for critical errors
CREATE OR REPLACE FUNCTION public.alert_on_critical_error() RETURNS TRIGGER AS $$
BEGIN
    -- Send webhook notification for critical errors
    PERFORM net.http_post(
        'YOUR_WEBHOOK_URL',
        jsonb_build_object(
            'text', 'CRITICAL ERROR: ' || NEW.error_message,
            'error_type', NEW.error_type,
            'timestamp', NEW.created_at
        )::text,
        '{"Content-Type": "application/json"}'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_alert_critical_error
    AFTER INSERT ON public.error_logs
    FOR EACH ROW
    WHEN (NEW.error_type IN ('AUTH_FAILURE', 'SIGNUP_ERROR', 'DATABASE_ERROR'))
    EXECUTE FUNCTION public.alert_on_critical_error();
```

## 3. External Monitoring Services

### Option A: Sentry Integration
```python
# Add to requirements.txt
sentry-sdk==1.40.0

# In your Flask app
import sentry_sdk
from sentry_sdk.integrations.flask import FlaskIntegration

sentry_sdk.init(
    dsn="YOUR_SENTRY_DSN",
    integrations=[FlaskIntegration()],
    traces_sample_rate=1.0,
    environment="production"
)
```

### Option B: Datadog/NewRelic
- Set up APM monitoring
- Configure alerts for error rates
- Monitor database performance

## 4. Log Monitoring

### Heroku Logplex Setup
```bash
# Install log monitoring addon
heroku addons:create logdna:quaco

# Or use Papertrail
heroku addons:create papertrail:choklad
```

### Custom Log Monitoring
```python
# Enhanced logging in auth.py
import logging
from datetime import datetime

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Add error tracking
def log_critical_error(error_type, error_message, user_id=None, extra_data=None):
    logger.error(f"CRITICAL: {error_type} - {error_message}", extra={
        'user_id': user_id,
        'error_type': error_type,
        'timestamp': datetime.utcnow().isoformat(),
        'extra_data': extra_data
    })
    
    # Send to external service
    # send_to_slack/discord/email(error_type, error_message)
```

## 5. Quick Setup Steps

1. **Immediate (5 min):**
   - Go to Supabase Dashboard → Settings → Monitoring
   - Add email alerts for API errors
   - Set threshold: >5 errors in 5 minutes

2. **Short-term (30 min):**
   - Set up Slack webhook
   - Add Discord notifications
   - Configure database alerts

3. **Long-term (1 hour):**
   - Integrate Sentry for detailed error tracking
   - Set up custom error logging table
   - Create monitoring dashboard

## 6. Alert Rules Examples

```json
{
  "api_errors": {
    "threshold": 5,
    "window": "5m",
    "channels": ["email", "slack"]
  },
  "auth_failures": {
    "threshold": 10,
    "window": "10m",
    "channels": ["email", "discord"]
  },
  "database_errors": {
    "threshold": 1,
    "window": "1m",
    "channels": ["email", "slack", "discord"]
  }
}
```

## 7. Testing Alerts

```sql
-- Test error logging
SELECT public.log_error('TEST_ERROR', 'Testing alert system', NULL, '/api/test', '{"test": true}');

-- Check logs
SELECT * FROM public.error_logs ORDER BY created_at DESC LIMIT 10;
```

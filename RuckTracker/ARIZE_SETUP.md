# Arize AI Observability Setup

This document explains how to set up and use Arize AI for LLM observability in the Rucking App.

## What is Arize AI?

Arize AI is an observability platform that helps you monitor, debug, and improve your LLM (Large Language Model) applications. It tracks:
- **Prompts** sent to OpenAI
- **Responses** received
- **Latency** (how long each call takes)
- **Token usage** (prompt tokens, completion tokens, total cost)
- **Metadata** (user IDs, session IDs, model versions, etc.)
- **Error rates** and failures

## Backend Setup (Python)

### 1. Install Arize SDK

The Arize SDK has been added to `dependencies.txt`:

```bash
cd /Users/rory/RuckingApp/RuckTracker
pip install -r dependencies.txt
```

Or install manually:
```bash
pip install arize
```

### 2. Get Arize API Keys

1. Sign up at [https://app.arize.com/](https://app.arize.com/)
2. Create a new space for "Rucking App"
3. Go to Settings → API Keys
4. Copy your **API Key** and **Space Key**

### 3. Configure Environment Variables

Add these to your Heroku config or `.env` file:

```bash
# Arize AI Configuration
ARIZE_API_KEY=your_api_key_here
ARIZE_SPACE_KEY=your_space_key_here
ARIZE_ENABLED=true
ARIZE_ENVIRONMENT=production  # or 'staging', 'development'
```

Set in Heroku:
```bash
heroku config:set ARIZE_API_KEY=your_api_key_here
heroku config:set ARIZE_SPACE_KEY=your_space_key_here
heroku config:set ARIZE_ENABLED=true
heroku config:set ARIZE_ENVIRONMENT=production
```

### 4. Integration Points

Arize observability has been integrated into:

#### AI Cheerleader (`/api/ai-cheerleader`)
- Tracks all motivational messages generated during rucks
- Logs personality type, coaching prompts, and user context
- Model: `rucking-llm-ai_cheerleader`

#### Notification Manager
- Tracks retention notifications (Session 1, Session 1→2, Road to 7)
- Model: `rucking-llm-notifications`

#### User Insights
- Tracks homepage AI insights generation
- Model: `rucking-llm-insights`

#### Coaching Plans
- Tracks coaching plan generation and updates
- Model: `rucking-llm-coaching`

### 5. What Gets Logged

For each LLM call, Arize logs:

```python
{
    "prediction_id": "uuid",
    "model": "gpt-5",
    "prompt": "Full prompt sent to OpenAI",
    "response": "Full response from OpenAI",
    "latency_ms": 1234.56,
    "user_id": "user-uuid",
    "session_id": "session-uuid",
    "context_type": "ai_cheerleader",
    "prompt_tokens": 100,
    "completion_tokens": 50,
    "total_tokens": 150,
    "temperature": 0.7,
    "max_tokens": 120,
    "metadata": {
        "personality": "encouraging",
        "has_coaching_prompt": true,
        "coaching_prompt_type": "intervals"
    }
}
```

### 6. Using the Arize Dashboard

Once configured, you can:

1. **Monitor Performance**
   - View latency distribution (P50, P95, P99)
   - Track token usage and costs
   - See error rates

2. **Debug Issues**
   - Search for specific user sessions
   - View full prompt/response pairs
   - Filter by context type (ai_cheerleader, coaching, etc.)

3. **Improve Prompts**
   - Compare prompt versions
   - A/B test different system prompts
   - Identify prompts that lead to timeouts or errors

4. **Cost Optimization**
   - Track token usage by context type
   - Identify expensive prompts
   - Optimize max_tokens settings

## Frontend Setup (Flutter - Optional)

The Flutter app currently calls the backend API (not OpenAI directly), so most logging happens on the backend. However, if you want to add frontend-specific observability:

### For Direct OpenAI Calls (if any remain)

If there are any direct OpenAI calls from Flutter that bypass the backend, you would need to:

1. Use HTTP interceptors to log requests
2. Send telemetry to your backend
3. Backend forwards to Arize

Currently, the AI cheerleader in Flutter calls `/api/ai-cheerleader`, which already has Arize logging, so no frontend changes are needed.

## Monitoring Models in Arize

You'll see these models in your Arize dashboard:

- **rucking-llm-ai_cheerleader**: Real-time motivational messages during rucks
- **rucking-llm-notifications**: Retention and milestone notifications
- **rucking-llm-insights**: Homepage AI insights and narratives
- **rucking-llm-coaching**: Coaching plan generation and updates

Each model can be monitored separately with its own dashboards and alerts.

## Disabling Arize

To disable Arize logging (e.g., in development):

```bash
heroku config:set ARIZE_ENABLED=false
```

Or locally:
```bash
ARIZE_ENABLED=false
```

Arize calls will be skipped, but your app will continue to function normally.

## Code Example

Here's how Arize is integrated in the code:

```python
from RuckTracker.services.arize_observability import observe_openai_call
import time

# Track timing
start_time = time.time()

# Call OpenAI
completion = openai_client.chat.completions.create(
    model="gpt-5",
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt},
    ],
    max_tokens=120,
    temperature=0.7,
)

latency_ms = (time.time() - start_time) * 1000

# Log to Arize
observe_openai_call(
    model="gpt-5",
    messages=[...],
    response=completion.choices[0].message.content,
    latency_ms=latency_ms,
    user_id=user_id,
    session_id=session_id,
    context_type='ai_cheerleader',
    prompt_tokens=completion.usage.prompt_tokens,
    completion_tokens=completion.usage.completion_tokens,
    total_tokens=completion.usage.total_tokens,
    temperature=0.7,
    max_tokens=120,
)
```

## Troubleshooting

### Arize not logging

Check:
1. `ARIZE_ENABLED=true` is set
2. `ARIZE_API_KEY` and `ARIZE_SPACE_KEY` are set correctly
3. Check logs for "Arize observability initialized" message
4. Verify the `arize` package is installed: `pip list | grep arize`

### Import errors

```bash
pip install arize --upgrade
```

### No data in Arize dashboard

- It can take 1-2 minutes for data to appear
- Make sure you're looking at the right environment (production vs staging)
- Check that LLM calls are actually being made

## Next Steps

1. Sign up for Arize
2. Get API keys
3. Set environment variables in Heroku
4. Deploy the updated code
5. Make some test rucks to generate AI cheerleader messages
6. View data in Arize dashboard

## Links

- Arize Dashboard: https://app.arize.com/
- Arize Docs: https://docs.arize.com/arize/
- Python SDK: https://docs.arize.com/arize/sdks/python-sdk

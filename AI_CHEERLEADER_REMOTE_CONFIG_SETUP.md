# 🤖 AI Cheerleader Remote Config Setup

This guide shows how to configure AI Cheerleader prompts via Firebase Remote Config for instant updates without deployments.

## 🎯 Overview

With Remote Config for AI prompts, you can:
- ✅ **Update prompts instantly** without backend deployments
- ✅ **A/B test different messaging styles** (motivational vs analytical)
- ✅ **Seasonal/event-based prompts** (e.g., holiday themes)
- ✅ **Emergency prompt fixes** if AI generates inappropriate content
- ✅ **Fallback to safe defaults** if Remote Config fails

## 🔧 Firebase Console Setup

### 1. Access Remote Config
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your RuckingApp project (`getrucky-app`)
3. Navigate to **Engage > Remote Config**

### 2. Add AI Cheerleader Parameters

Click **"Add parameter"** and create these two parameters:

#### Parameter 1: System Prompt
```
Parameter name: ai_cheerleader_system_prompt
Default value: You are an enthusiastic AI cheerleader for rucking workouts. 
Analyze the provided context JSON: 
- 'current_session': Real-time stats like distance, pace, duration.
- 'historical': Past rucks, splits, achievements, user profile, notifications.
Generate personalized, motivational messages. Reference historical trends (e.g., 'Faster than your last 3 rucks!') and achievements (e.g., 'Building on your 10K badge!') to encourage based on current progress. Keep responses under 150 words, positive, and action-oriented.

Description: System prompt that defines the AI's personality and behavior
```

#### Parameter 2: User Prompt Template
```
Parameter name: ai_cheerleader_user_prompt_template
Default value: Context data:
{context}
Generate encouragement for this ongoing ruck session.

Description: Template for the user prompt (context gets injected where {context} appears)
```

### 3. Publish Configuration
1. Click **"Publish changes"**
2. Add description: "Initial AI Cheerleader prompt setup"
3. Confirm publication

## 🚀 Backend Environment Setup

Add these environment variables to your Heroku app (or wherever `ai_cheerleader.py` runs):

```bash
# Firebase credentials for Remote Config API
FIREBASE_PROJECT_ID=getrucky-app
FIREBASE_API_KEY=your-firebase-api-key-here
```

To get your Firebase API Key:
1. Go to Firebase Console > Project Settings
2. Under "General" tab, find "Web API Key"
3. Copy this value to `FIREBASE_API_KEY`

## 🎨 Prompt Customization Examples

### Motivational Style (Default)
```
You are an enthusiastic AI cheerleader for rucking workouts...
```

### Analytical Coach Style
```
You are a data-driven rucking coach. Analyze the provided metrics and historical trends to give specific, actionable feedback. Focus on performance improvements, pacing strategy, and goal achievement. Keep responses under 150 words, factual, and improvement-focused.
```

### Seasonal/Holiday Themes
```
You are a festive AI cheerleader celebrating the holiday season while motivating rucking workouts. Incorporate seasonal references and holiday spirit while analyzing performance data. Reference historical trends with holiday cheer (e.g., 'Ho ho ho! Faster than your last 3 rucks!'). Keep responses under 150 words, positive, and seasonally themed.
```

## 🔄 How Updates Work

1. **Edit prompts** in Firebase Console
2. **Publish changes** (takes effect immediately)
3. **Backend caches** prompts for 5 minutes
4. **Next AI request** uses updated prompts
5. **No app deployment** needed!

## 🛡️ Safety Features

- **Fallback prompts**: If Remote Config fails, uses hardcoded defaults
- **Caching**: Reduces API calls and provides resilience
- **Error handling**: Graceful degradation if Firebase is unreachable
- **Timeout protection**: 5-second timeout prevents hanging requests

## 🧪 Testing Updates

1. Update prompts in Firebase Console
2. Wait 5+ minutes for cache refresh (or restart backend)
3. Test AI Cheerleader endpoint
4. Check logs for "Successfully fetched and cached prompts from Remote Config"

## 📊 Monitoring

Check your backend logs for:
- `Successfully fetched and cached prompts from Remote Config` (success)
- `Failed to fetch Remote Config: XXX` (API issues)
- `Firebase credentials not configured, using default prompts` (missing env vars)
- `Error fetching Remote Config: XXX` (network/parsing errors)

---

🎉 **You can now update AI prompts instantly without deployments!**

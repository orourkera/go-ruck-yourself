# Sentry Issues Manager Setup

This tool allows you to fetch open issues from Sentry and mark them as resolved after fixing them, creating a seamless workflow with Claude Code for issue resolution.

## 🚀 Quick Setup

### 1. Create Configuration File

Copy the template and fill in your details:

```bash
cp .sentry_config.json.template .sentry_config.json
```

### 2. Get Your Sentry API Token

1. Go to **Sentry** > **Settings** > **Account** > **API** > **Auth Tokens**
2. Click **"Create New Token"**
3. Name it something like "Claude Code Integration"
4. Select these scopes:
   - ✅ `project:read` - to fetch issues
   - ✅ `project:write` - to mark issues as resolved
5. Copy the token

### 3. Find Your Organization & Project Slugs

- **Organization Slug**: Found in your Sentry URL: `sentry.io/organizations/YOUR_ORG_SLUG/`
- **Project Slug**: Found in your project URL: `.../projects/YOUR_PROJECT_SLUG/`

### 4. Fill in `.sentry_config.json`

```json
{
  "api_token": "your-actual-sentry-token-here",
  "organization_slug": "your-org-slug",
  "project_slug": "your-project-slug"
}
```

## 📋 Usage

### Fetch All Open Issues
```bash
python sentry_manager.py fetch
```
This will:
- Pull all open issues from Sentry
- Calculate priority scores based on frequency, severity, and user impact
- Generate a formatted summary perfect for Claude analysis
- Save data to `sentry_issues.json`

### Show Summary of Fetched Issues
```bash
python sentry_manager.py summary
```
Shows a nicely formatted summary of previously fetched issues.

### Mark Issue as Resolved
```bash
python sentry_manager.py resolve ABC123
```
Marks the specific issue (by Sentry short ID) as resolved.

### Mark ALL Issues as Resolved
```bash
python sentry_manager.py resolve --all
```
⚠️  Use carefully! This marks ALL fetched issues as resolved in Sentry.

## 🔄 Recommended Workflow

1. **Fetch Issues**:
   ```bash
   python sentry_manager.py fetch
   ```

2. **Copy the output summary to Claude** and ask for analysis & fixes

3. **Implement the fixes** in your code based on Claude's suggestions

4. **Mark issues as resolved**:
   ```bash
   python sentry_manager.py resolve ABC123
   # or resolve all at once:
   python sentry_manager.py resolve --all
   ```

5. **Commit and deploy** your fixes

## 🎯 Priority Scoring

Issues are automatically scored based on:

- **Frequency (0-40 pts)**: How often the error occurs
- **Severity (0-30 pts)**: Error level (fatal=30, error=25, warning=15, etc.)  
- **User Impact (0-20 pts)**: Number of unique users affected
- **Recency (0-10 pts)**: How recently the error occurred

**Priority Categories**:
- 🔴 **Critical (60+ pts)**: Fix immediately
- 🟠 **High (40-59 pts)**: Fix soon
- 🟡 **Medium (20-39 pts)**: Fix when convenient
- 🟢 **Low (<20 pts)**: Fix eventually

## 🔒 Security

- `.sentry_config.json` is automatically gitignored to protect your API token
- Issue data files are also gitignored to prevent accidentally committing sensitive error details

## 🛠️ Troubleshooting

**"Config file not found"**
- Make sure you copied `.sentry_config.json.template` to `.sentry_config.json` and filled in your details

**"API request failed"**
- Check that your API token has the right scopes (`project:read` and `project:write`)
- Verify your organization and project slugs are correct
- Make sure your token hasn't expired

**"No issues found"**
- Great! That means you have no open issues in Sentry
- Or check that you're looking at the right project

## 📊 Example Output

```
🚨 SENTRY ISSUES SUMMARY 🚨
═══════════════════════════════════════════

Total Open Issues: 5
Fetched: 2025-01-02T10:30:00

Priority Breakdown:
🔴 Critical (60+ points): 2 issues
🟠 High (40-59 points): 1 issue  
🟡 Medium (20-39 points): 2 issues
🟢 Low (<20 points): 0 issues

🎯 TOP PRIORITY ISSUES TO FIX:

1. 🔴 Flutter widget build error
   • ID: ABC123 | Score: 85.2
   • Location: lib/widgets/stats_chart.dart:179
   • Level: ERROR | Count: 47 | Users: 12
   • Last Seen: 2025-01-02T09:45:00
   • Platform: flutter

2. 🔴 API timeout in session sync  
   • ID: DEF456 | Score: 72.1
   • Location: lib/services/api_client.dart:234
   • Level: ERROR | Count: 23 | Users: 8
   • Last Seen: 2025-01-02T08:30:00
   • Platform: flutter
```

Ready to start fixing bugs more efficiently! 🐛✨
#!/usr/bin/env python3
"""
Sentry Issues Manager for Claude Code Integration
Fetches open issues from Sentry API and marks them as resolved after fixes.

Usage:
    python sentry_manager.py fetch                    # Fetch all open issues
    python sentry_manager.py resolve <issue_id>       # Mark specific issue as resolved
    python sentry_manager.py resolve --all            # Mark all fetched issues as resolved
    python sentry_manager.py summary                  # Show summary of fetched issues
"""

import json
import os
import sys
import requests
import argparse
from datetime import datetime
from typing import List, Dict, Any, Optional

class SentryManager:
    def __init__(self, config_file: str = '.sentry_config.json'):
        self.config_file = config_file
        self.config = self._load_config()
        self.base_url = 'https://sentry.io/api/0'
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {self.config["api_token"]}',
            'Content-Type': 'application/json'
        })
        self.issues_file = 'sentry_issues.json'
    
    def _load_config(self) -> Dict[str, str]:
        """Load Sentry configuration from file or environment variables."""
        # Try environment variables first (more secure)
        api_token = os.getenv('SENTRY_API_TOKEN')
        if api_token:
            return {
                "api_token": api_token,
                "organization_slug": "get-rucky-llc", 
                "project_slug": "ruck"
            }
        
        # Fallback to config file
        if not os.path.exists(self.config_file):
            self._create_config_template()
            print(f"❌ Config file not found. Created template at {self.config_file}")
            print("Please fill in your Sentry details and run again.")
            print("Or set SENTRY_API_TOKEN environment variable.")
            sys.exit(1)
        
        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)
            
            required_fields = ['api_token', 'organization_slug', 'project_slug']
            for field in required_fields:
                if not config.get(field):
                    print(f"❌ Missing required field '{field}' in {self.config_file}")
                    sys.exit(1)
            
            return config
        except json.JSONDecodeError as e:
            print(f"❌ Invalid JSON in {self.config_file}: {e}")
            sys.exit(1)
    
    def _create_config_template(self):
        """Create a template configuration file."""
        template = {
            "api_token": "YOUR_SENTRY_API_TOKEN_HERE",
            "organization_slug": "your-org-slug",
            "project_slug": "your-project-slug",
            "notes": {
                "api_token": "Get this from Sentry > Settings > Account > API > Auth Tokens",
                "organization_slug": "Found in your Sentry URL: sentry.io/organizations/YOUR_ORG_SLUG/",
                "project_slug": "Found in your project URL: .../projects/YOUR_PROJECT_SLUG/"
            }
        }
        
        with open(self.config_file, 'w') as f:
            json.dump(template, f, indent=2)
    
    def _make_request(self, endpoint: str, method: str = 'GET', data: Dict = None) -> Optional[Dict]:
        """Make authenticated request to Sentry API."""
        url = f"{self.base_url}{endpoint}"
        
        try:
            if method == 'GET':
                response = self.session.get(url)
            elif method == 'PUT':
                response = self.session.put(url, json=data)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")
            
            response.raise_for_status()
            return response.json() if response.content else {}
            
        except requests.exceptions.RequestException as e:
            print(f"❌ API request failed: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error details: {error_detail}")
                except:
                    print(f"   Status code: {e.response.status_code}")
                    print(f"   Response: {e.response.text}")
            return None
    
    def fetch_issues(self) -> List[Dict[str, Any]]:
        """Fetch all open issues from Sentry."""
        org_slug = self.config['organization_slug']
        project_slug = self.config['project_slug']
        
        print(f"🔍 Fetching open issues from {org_slug}/{project_slug}...")
        
        all_issues = []
        cursor = None
        
        while True:
            # Build endpoint with pagination
            endpoint = f"/projects/{org_slug}/{project_slug}/issues/"
            params = {
                'statsPeriod': '14d',  # Last 14 days of stats
                'query': 'is:unresolved',  # Only unresolved issues
                'sort': 'freq',  # Sort by frequency
                'limit': 100  # Max per page
            }
            
            if cursor:
                params['cursor'] = cursor
            
            # Add query parameters to URL
            query_string = '&'.join([f"{k}={v}" for k, v in params.items()])
            full_endpoint = f"{endpoint}?{query_string}"
            
            response_data = self._make_request(full_endpoint)
            if not response_data:
                break
            
            issues = response_data if isinstance(response_data, list) else response_data.get('data', [])
            all_issues.extend(issues)
            
            print(f"   Fetched {len(issues)} issues (total: {len(all_issues)})")
            
            # Check for pagination
            if isinstance(response_data, dict):
                cursor = response_data.get('links', {}).get('next', {}).get('cursor')
                if not cursor:
                    break
            else:
                break  # No pagination info, assuming we got everything
        
        print(f"✅ Fetched {len(all_issues)} total open issues")
        
        # Enrich issues with additional data
        enriched_issues = []
        for issue in all_issues:
            enriched_issue = self._enrich_issue(issue)
            if enriched_issue:
                enriched_issues.append(enriched_issue)
        
        # Save issues to file
        issue_data = {
            'fetched_at': datetime.now().isoformat(),
            'total_issues': len(enriched_issues),
            'issues': enriched_issues
        }
        
        with open(self.issues_file, 'w') as f:
            json.dump(issue_data, f, indent=2, default=str)
        
        print(f"💾 Saved issues to {self.issues_file}")
        
        return enriched_issues
    
    def _enrich_issue(self, issue: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Enrich issue with additional metadata for better analysis."""
        try:
            # Calculate priority score
            priority_score = self._calculate_priority(issue)
            
            # Extract useful metadata
            enriched = {
                'id': issue.get('id'),
                'shortId': issue.get('shortId'),
                'title': issue.get('title', 'Unknown Error'),
                'culprit': issue.get('culprit', 'Unknown location'),
                'level': issue.get('level', 'error'),
                'status': issue.get('status', 'unresolved'),
                'count': issue.get('count', 0),
                'userCount': issue.get('userCount', 0),
                'firstSeen': issue.get('firstSeen'),
                'lastSeen': issue.get('lastSeen'),
                'permalink': issue.get('permalink', ''),
                'priority_score': priority_score,
                'platform': issue.get('platform'),
                'type': issue.get('type', 'error'),
                'metadata': issue.get('metadata', {}),
                'tags': {tag.get('key', ''): tag.get('value', '') for tag in issue.get('tags', [])},
                'annotations': issue.get('annotations', []),
                'assignee': issue.get('assignee', {}).get('name') if issue.get('assignee') else None,
            }
            
            return enriched
            
        except Exception as e:
            print(f"⚠️  Error enriching issue {issue.get('id', 'unknown')}: {e}")
            return None
    
    def _calculate_priority(self, issue: Dict[str, Any]) -> float:
        """Calculate priority score based on frequency, severity, and user impact."""
        score = 0.0
        
        # Frequency score (0-40 points)
        count = int(issue.get('count', 0) or 0)
        if count > 100:
            score += 40
        elif count > 50:
            score += 30
        elif count > 10:
            score += 20
        elif count > 1:
            score += 10
        
        # Level score (0-30 points)
        level = issue.get('level', 'error')
        level_scores = {
            'fatal': 30,
            'error': 25,
            'warning': 15,
            'info': 5,
            'debug': 2
        }
        score += level_scores.get(level, 10)
        
        # User impact score (0-20 points)
        user_count = int(issue.get('userCount', 0) or 0)
        if user_count > 50:
            score += 20
        elif user_count > 20:
            score += 15
        elif user_count > 5:
            score += 10
        elif user_count > 1:
            score += 5
        
        # Recency score (0-10 points)
        last_seen = issue.get('lastSeen')
        if last_seen:
            try:
                from datetime import datetime, timezone
                last_seen_dt = datetime.fromisoformat(last_seen.replace('Z', '+00:00'))
                hours_ago = (datetime.now(timezone.utc) - last_seen_dt).total_seconds() / 3600
                
                if hours_ago < 1:
                    score += 10  # Very recent
                elif hours_ago < 24:
                    score += 7   # Last day
                elif hours_ago < 168:  # Last week
                    score += 4
                elif hours_ago < 720:  # Last month
                    score += 2
            except:
                pass
        
        return round(score, 1)
    
    def generate_summary(self, issues: List[Dict[str, Any]] = None) -> str:
        """Generate a formatted summary of issues for Claude analysis."""
        if issues is None:
            if not os.path.exists(self.issues_file):
                return "❌ No issues data found. Run 'fetch' command first."
            
            with open(self.issues_file, 'r') as f:
                data = json.load(f)
                issues = data.get('issues', [])
        
        fetched_at = datetime.now().strftime('%Y-%m-%d %H:%M:%S') if issues else 'Unknown'
        
        if not issues:
            return "✅ No open issues found!"
        
        # Sort by priority score (highest first)
        issues.sort(key=lambda x: x.get('priority_score', 0), reverse=True)
        
        # Categorize issues
        critical_issues = [i for i in issues if i.get('priority_score', 0) >= 60]
        high_issues = [i for i in issues if 40 <= i.get('priority_score', 0) < 60]
        medium_issues = [i for i in issues if 20 <= i.get('priority_score', 0) < 40]
        low_issues = [i for i in issues if i.get('priority_score', 0) < 20]
        
        summary = f"""
🚨 **SENTRY ISSUES SUMMARY** 🚨
═══════════════════════════════════════════════════════════════════════════════════════════════════

**Total Open Issues:** {len(issues)}
**Fetched:** {fetched_at}

**Priority Breakdown:**
🔴 Critical (60+ points): {len(critical_issues)} issues
🟠 High (40-59 points): {len(high_issues)} issues  
🟡 Medium (20-39 points): {len(medium_issues)} issues
🟢 Low (<20 points): {len(low_issues)} issues

═══════════════════════════════════════════════════════════════════════════════════════════════════

"""

        # Add detailed breakdown for critical and high priority issues
        if critical_issues or high_issues:
            summary += "🎯 **TOP PRIORITY ISSUES TO FIX:**\n\n"
            
            priority_issues = critical_issues + high_issues
            for i, issue in enumerate(priority_issues[:10], 1):  # Top 10
                priority_icon = "🔴" if issue.get('priority_score', 0) >= 60 else "🟠"
                summary += f"""**{i}. {priority_icon} {issue['title']}**
   • **ID:** {issue['shortId']} | **Score:** {issue.get('priority_score', 0)}
   • **Location:** {issue['culprit']}
   • **Level:** {issue['level'].upper()} | **Count:** {issue['count']} | **Users:** {issue['userCount']}
   • **Last Seen:** {issue['lastSeen']}
   • **Link:** {issue['permalink']}
   • **Platform:** {issue.get('platform', 'unknown')}
   
"""
        
        summary += f"""
═══════════════════════════════════════════════════════════════════════════════════════════════════

🤖 **FOR CLAUDE:**
Please analyze these Sentry issues and help me prioritize fixes. Focus on the critical and high priority issues first.

For each issue you want to investigate further, I can:
1. Show you the full error details and stack traces
2. Search for the relevant code in the codebase
3. Implement fixes
4. Mark issues as resolved once fixed

Ready to start fixing! Which issue should we tackle first?

═══════════════════════════════════════════════════════════════════════════════════════════════════
"""

        return summary.strip()
    
    def resolve_issue(self, issue_id: str) -> bool:
        """Mark a specific issue as resolved in Sentry."""
        org_slug = self.config['organization_slug']
        
        print(f"✅ Marking issue {issue_id} as resolved...")
        
        # Use the correct organization-based endpoint as per Sentry API docs
        endpoint = f"/organizations/{org_slug}/issues/{issue_id}/"
        data = {
            'status': 'resolved',
            'statusDetails': {}
        }
        
        response = self._make_request(endpoint, method='PUT', data=data)
        
        if response is not None:
            print(f"✅ Successfully resolved issue {issue_id}")
            return True
        else:
            print(f"❌ Failed to resolve issue {issue_id}")
            return False
    
    def resolve_all_issues(self) -> int:
        """Mark all fetched issues as resolved."""
        if not os.path.exists(self.issues_file):
            print("❌ No issues data found. Run 'fetch' command first.")
            return 0
        
        with open(self.issues_file, 'r') as f:
            data = json.load(f)
            issues = data.get('issues', [])
        
        if not issues:
            print("✅ No issues to resolve.")
            return 0
        
        print(f"🔄 Resolving {len(issues)} issues...")
        
        resolved_count = 0
        for issue in issues:
            issue_id = issue.get('shortId') or issue.get('id')
            if issue_id and self.resolve_issue(issue_id):
                resolved_count += 1
        
        print(f"✅ Successfully resolved {resolved_count}/{len(issues)} issues")
        return resolved_count

def main():
    parser = argparse.ArgumentParser(description='Sentry Issues Manager for Claude Code Integration')
    parser.add_argument('command', choices=['fetch', 'resolve', 'summary'], 
                       help='Command to execute')
    parser.add_argument('issue_id', nargs='?', 
                       help='Issue ID to resolve (for resolve command)')
    parser.add_argument('--all', action='store_true', 
                       help='Resolve all fetched issues (for resolve command)')
    parser.add_argument('--config', default='.sentry_config.json',
                       help='Path to config file (default: .sentry_config.json)')
    
    args = parser.parse_args()
    
    try:
        manager = SentryManager(args.config)
        
        if args.command == 'fetch':
            issues = manager.fetch_issues()
            print(f"\n{manager.generate_summary(issues)}")
            
        elif args.command == 'resolve':
            if args.all:
                manager.resolve_all_issues()
            elif args.issue_id:
                manager.resolve_issue(args.issue_id)
            else:
                print("❌ Please specify an issue ID or use --all flag")
                sys.exit(1)
                
        elif args.command == 'summary':
            print(manager.generate_summary())
    
    except KeyboardInterrupt:
        print("\n👋 Interrupted by user")
        sys.exit(0)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
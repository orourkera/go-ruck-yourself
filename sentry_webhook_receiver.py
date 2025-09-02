#!/usr/bin/env python3
"""
Sentry Webhook Receiver for Claude Code Integration
Receives Sentry webhooks and formats them for easy copy-paste to Claude conversations.
"""

import json
import logging
from datetime import datetime
from flask import Flask, request, jsonify
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
WEBHOOK_PORT = 8080
ERRORS_FILE = "sentry_errors.txt"
MAX_ERRORS_IN_FILE = 50

def format_sentry_error(webhook_data):
    """Format Sentry error data for Claude conversation."""
    try:
        # Extract key information from webhook
        if 'data' in webhook_data and 'issue' in webhook_data['data']:
            issue = webhook_data['data']['issue']
            
            # Basic issue info
            title = issue.get('title', 'Unknown Error')
            level = issue.get('level', 'error')
            project = issue.get('project', {}).get('name', 'unknown')
            
            # Error details
            culprit = issue.get('culprit', 'Unknown location')
            short_id = issue.get('shortId', 'N/A')
            permalink = issue.get('permalink', '')
            
            # Event count and first/last seen
            count = issue.get('count', 0)
            first_seen = issue.get('firstSeen', '')
            last_seen = issue.get('lastSeen', '')
            
            # Tags for context
            tags = {}
            if 'tags' in issue:
                for tag in issue['tags']:
                    tags[tag.get('key', '')] = tag.get('value', '')
            
            # Format the error for Claude
            formatted_error = f"""
🚨 **SENTRY ERROR ALERT** 🚨
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Error:** {title}
**Level:** {level.upper()}
**Project:** {project}
**Location:** {culprit}
**Sentry ID:** {short_id}
**Count:** {count} occurrences
**First Seen:** {first_seen}
**Last Seen:** {last_seen}

**Link:** {permalink}

**Context Tags:**
{format_tags(tags)}

**Priority:** {"🔴 HIGH" if level in ['error', 'fatal'] else "🟡 MEDIUM" if level == 'warning' else "🟢 LOW"}

**Timestamp:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Please analyze and fix this error. Let me know if you need more details from Sentry.

"""
            return formatted_error.strip()
            
    except Exception as e:
        logger.error(f"Error formatting Sentry webhook: {e}")
        return f"Error formatting Sentry webhook data: {e}\n\nRaw data: {json.dumps(webhook_data, indent=2)}"
    
    return f"Unable to parse Sentry webhook.\n\nRaw data: {json.dumps(webhook_data, indent=2)}"

def format_tags(tags):
    """Format tags dictionary for display."""
    if not tags:
        return "None"
    
    formatted = []
    for key, value in tags.items():
        formatted.append(f"  • {key}: {value}")
    
    return "\n".join(formatted)

def save_error_to_file(formatted_error):
    """Save formatted error to file, maintaining a rolling buffer."""
    try:
        # Read existing errors
        existing_errors = []
        if os.path.exists(ERRORS_FILE):
            with open(ERRORS_FILE, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                if content:
                    existing_errors = content.split('\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n')
        
        # Add new error to the beginning
        existing_errors.insert(0, formatted_error)
        
        # Keep only the most recent MAX_ERRORS_IN_FILE errors
        if len(existing_errors) > MAX_ERRORS_IN_FILE:
            existing_errors = existing_errors[:MAX_ERRORS_IN_FILE]
        
        # Write back to file
        with open(ERRORS_FILE, 'w', encoding='utf-8') as f:
            f.write('\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'.join(existing_errors))
        
        logger.info(f"Saved error to {ERRORS_FILE}")
        
    except Exception as e:
        logger.error(f"Failed to save error to file: {e}")

@app.route('/sentry-webhook', methods=['POST'])
def handle_sentry_webhook():
    """Handle incoming Sentry webhooks."""
    try:
        # Get webhook data
        webhook_data = request.get_json()
        
        if not webhook_data:
            return jsonify({'error': 'No data received'}), 400
        
        # Log the webhook for debugging
        logger.info(f"Received Sentry webhook: {webhook_data.get('action', 'unknown action')}")
        
        # Only process issue events (not comments, etc.)
        if webhook_data.get('action') in ['created', 'resolved', 'assigned']:
            formatted_error = format_sentry_error(webhook_data)
            
            # Print to console for immediate visibility
            print("\n" + "="*80)
            print("NEW SENTRY ERROR - COPY TO CLAUDE:")
            print("="*80)
            print(formatted_error)
            print("="*80 + "\n")
            
            # Save to file for later reference
            save_error_to_file(formatted_error)
            
            return jsonify({'status': 'processed', 'action': webhook_data.get('action')})
        else:
            logger.info(f"Ignoring webhook action: {webhook_data.get('action')}")
            return jsonify({'status': 'ignored', 'reason': 'not an issue event'})
            
    except Exception as e:
        logger.error(f"Error processing Sentry webhook: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'errors_file': ERRORS_FILE,
        'errors_file_exists': os.path.exists(ERRORS_FILE)
    })

@app.route('/recent-errors', methods=['GET'])
def get_recent_errors():
    """Get recent errors from file."""
    try:
        if not os.path.exists(ERRORS_FILE):
            return jsonify({'errors': []})
        
        with open(ERRORS_FILE, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            if not content:
                return jsonify({'errors': []})
            
            errors = content.split('\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n')
            return jsonify({'errors': errors[:10]})  # Return most recent 10
            
    except Exception as e:
        logger.error(f"Error reading recent errors: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print(f"""
🚀 Sentry Webhook Receiver Started!

📍 Webhook URL: http://localhost:{WEBHOOK_PORT}/sentry-webhook
🔍 Health Check: http://localhost:{WEBHOOK_PORT}/health  
📋 Recent Errors: http://localhost:{WEBHOOK_PORT}/recent-errors
📁 Errors File: {ERRORS_FILE}

Configure this URL in your Sentry project webhooks settings.
""")
    
    app.run(host='0.0.0.0', port=WEBHOOK_PORT, debug=False)
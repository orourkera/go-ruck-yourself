#!/usr/bin/env python3
"""
Quick script to find Sentry organization and project slugs using the API
"""

import requests
import json

# Your API token - DO NOT COMMIT THIS FILE WITH REAL TOKEN
API_TOKEN = "YOUR_SENTRY_API_TOKEN_HERE"

headers = {
    'Authorization': f'Bearer {API_TOKEN}',
    'Content-Type': 'application/json'
}

print("🔍 Finding your Sentry organization and project slugs...\n")

# Get organizations
print("📋 Your organizations:")
try:
    response = requests.get('https://sentry.io/api/0/organizations/', headers=headers)
    response.raise_for_status()
    orgs = response.json()
    
    for org in orgs:
        print(f"  • Organization: {org['name']} (slug: {org['slug']})")
        org_slug = org['slug']
        
        # Get projects for this org
        print(f"    Projects in {org['name']}:")
        projects_response = requests.get(f'https://sentry.io/api/0/organizations/{org_slug}/projects/', headers=headers)
        projects_response.raise_for_status()
        projects = projects_response.json()
        
        for project in projects:
            print(f"      • Project: {project['name']} (slug: {project['slug']})")
        
        print()

except requests.exceptions.RequestException as e:
    print(f"❌ Error: {e}")
    if hasattr(e, 'response') and e.response is not None:
        print(f"   Status: {e.response.status_code}")
        print(f"   Response: {e.response.text}")
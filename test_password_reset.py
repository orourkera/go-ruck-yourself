#!/usr/bin/env python3
"""
Test script to verify password reset functionality
"""

import requests
import json

# Test the password reset endpoint
def test_password_reset():
    base_url = "https://get-rucky-staging-a362104b0255.herokuapp.com"
    
    # Test data
    test_email = "test@example.com"
    
    print(f"🧪 Testing password reset for: {test_email}")
    print(f"📡 Using backend: {base_url}")
    
    try:
        # Send password reset request
        response = requests.post(
            f"{base_url}/auth/password-reset",
            json={"email": test_email},
            headers={"Content-Type": "application/json"}
        )
        
        print(f"\n📊 Response Status: {response.status_code}")
        print(f"📄 Response Headers: {dict(response.headers)}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Success: {data['message']}")
            print("\n🔗 The password reset email should now contain:")
            print("   Redirect URL: com.getrucky.app://auth/callback")
            print("   This should launch the mobile app directly!")
        else:
            print(f"❌ Failed: {response.status_code}")
            try:
                error_data = response.json()
                print(f"   Error: {error_data}")
            except:
                print(f"   Raw response: {response.text}")
                
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error: {e}")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

if __name__ == "__main__":
    print("🔐 Password Reset Test Script")
    print("=" * 40)
    test_password_reset()

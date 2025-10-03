#!/usr/bin/env python3
"""
Test script to verify Arize AI integration is working
"""
import os
import sys
import time
from datetime import datetime
import uuid

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from RuckTracker.services.arize_observability import arize_observer

def test_arize_connection():
    """Test if Arize is configured and can log data"""

    print("=" * 60)
    print("Arize AI Integration Test")
    print("=" * 60)

    # Check configuration
    print("\n1. Checking Configuration...")
    print(f"   ARIZE_ENABLED: {os.getenv('ARIZE_ENABLED')}")
    print(f"   ARIZE_API_KEY: {'✓ Set' if os.getenv('ARIZE_API_KEY') else '✗ Not Set'}")
    print(f"   ARIZE_SPACE_ID: {'✓ Set' if os.getenv('ARIZE_SPACE_ID') else '✗ Not Set'}")
    print(f"   ARIZE_ENVIRONMENT: {os.getenv('ARIZE_ENVIRONMENT', 'production')}")

    # Check if observer is initialized
    print("\n2. Checking Observer Initialization...")
    if arize_observer.client:
        print("   ✓ Arize client initialized successfully")
    else:
        print("   ✗ Arize client NOT initialized")
        print("   Reasons:")
        if not os.getenv('ARIZE_ENABLED', 'false').lower() == 'true':
            print("   - ARIZE_ENABLED is not set to 'true'")
        if not os.getenv('ARIZE_API_KEY'):
            print("   - ARIZE_API_KEY is not set")
        if not os.getenv('ARIZE_SPACE_ID'):
            print("   - ARIZE_SPACE_ID is not set")
        return False

    # Send test log
    print("\n3. Sending Test Log to Arize...")
    test_prompt = "You are a helpful AI assistant. Respond with 'Hello World'"
    test_response = "Hello World! This is a test from the Rucking App."

    result = arize_observer.log_llm_call(
        model='gpt-4-test',
        prompt=test_prompt,
        response=test_response,
        latency_ms=123.45,
        user_id='test-user',
        session_id=str(uuid.uuid4()),
        context_type='test',
        prompt_tokens=15,
        completion_tokens=10,
        total_tokens=25,
        temperature=0.7,
        max_tokens=100,
        metadata={
            'test': True,
            'timestamp': datetime.utcnow().isoformat(),
        }
    )

    if result:
        print("   ✓ Test log sent successfully!")
        print("\n4. Next Steps:")
        print("   - Go to https://app.arize.com/")
        print("   - Look for model: 'rucking-llm-test'")
        print("   - Check for the test prediction that was just sent")
        print("   - It may take 1-2 minutes for data to appear")
    else:
        print("   ✗ Failed to send test log")
        print("   Check the logs above for error details")
        return False

    print("\n" + "=" * 60)
    print("Test Complete!")
    print("=" * 60)

    return True

if __name__ == '__main__':
    # Load environment variables
    from dotenv import load_dotenv
    load_dotenv()

    success = test_arize_connection()
    sys.exit(0 if success else 1)

#!/usr/bin/env python3
"""
Test script for memory profiler endpoints
"""
import requests
import json
import time

# Your Heroku app URL
BASE_URL = "https://rucktracker-api.herokuapp.com"

def test_memory_endpoints():
    """Test all memory profiler endpoints"""
    
    print("🔧 Testing Memory Profiler Endpoints\n")
    
    # 1. Check current memory status
    print("1. Checking current memory status...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Current memory: {data['memory_mb']:.2f}MB ({data['memory_percent']:.1f}%)")
            print(f"   Python objects: {data['python_objects']['total_objects']:,}")
            print(f"   Top objects: {dict(data['python_objects']['top_objects'][:3])}")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 2. Start profiling
    print("2. Starting memory profiling...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/start-profiling")
        if response.status_code == 200:
            print("✅ Memory profiling started")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 3. Wait a bit for some activity
    print("3. Waiting 30 seconds for some API activity...")
    time.sleep(30)
    
    # 4. Take a snapshot
    print("4. Taking memory snapshot...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/snapshot")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Snapshot taken - Total snapshots: {data['snapshots_count']}")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 5. Stop profiling and get report
    print("5. Stopping profiling and getting detailed report...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/stop-profiling")
        if response.status_code == 200:
            data = response.json()
            print("✅ Profiling stopped")
            
            if 'final_report' in data:
                report = data['final_report']
                print(f"\n📊 MEMORY ANALYSIS REPORT:")
                print(f"   Final memory: {report['memory_mb']:.2f}MB")
                print(f"   CPU usage: {report['cpu_percent']:.1f}%")
                
                if 'top_memory_lines' in report:
                    print(f"\n🔥 TOP MEMORY CONSUMING CODE:")
                    for i, line in enumerate(report['top_memory_lines'][:5], 1):
                        print(f"   {i}. {line['file']} - {line['size_mb']:.2f}MB ({line['count']} objects)")
                
                if 'memory_diff' in report:
                    print(f"\n📈 MEMORY GROWTH ANALYSIS:")
                    for line in report['memory_diff'][:3]:
                        if line['size_diff_mb'] > 0:
                            print(f"   📈 {line['file']} - +{line['size_diff_mb']:.2f}MB")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 6. Force cleanup
    print("6. Testing memory cleanup...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/cleanup")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Cleaned up {data['objects_collected']} objects")
            print(f"   Memory after cleanup: {data['memory_mb_after_cleanup']:.2f}MB")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print("\n🎯 Memory profiler test complete!")
    print("\nNow you can:")
    print("- Monitor memory in real-time at /api/system/memory")
    print("- Start profiling before high-load periods")
    print("- Identify memory-hungry functions and code lines")
    print("- Track down memory leaks with snapshot comparisons")

if __name__ == "__main__":
    test_memory_endpoints()

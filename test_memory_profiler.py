#!/usr/bin/env python3
"""
Test script for AUTOMATIC memory profiler endpoints
"""
import requests
import json
import time

# Your Heroku app URL
BASE_URL = "https://rucktracker-api.herokuapp.com"

def test_automatic_memory_profiler():
    """Test all AUTOMATIC memory profiler endpoints"""
    
    print("🔧 Testing AUTOMATIC Memory Profiler (No Decorators Needed!)\n")
    
    # 1. Check current memory status
    print("1. Checking current memory status...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Current memory: {data['memory_mb']:.2f}MB ({data['memory_percent']:.1f}%)")
            print(f"   Python objects: {data['python_objects']['total_objects']:,}")
            print(f"   Top objects: {dict(data['python_objects']['top_objects'][:3])}")
            
            if data.get('memory_hotspots'):
                print(f"\n🔥 TOP MEMORY HOTSPOTS (automatically detected):")
                for hotspot in data['memory_hotspots'][:3]:
                    print(f"   • {hotspot['file_line']} - {hotspot['memory_mb']:.2f}MB")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 2. Start automatic profiling
    print("2. Starting AUTOMATIC memory profiling (tracks ALL functions)...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/start-auto-profiling")
        if response.status_code == 200:
            print("✅ Automatic memory profiling started - ALL functions being tracked!")
            print("   No decorators needed - discovers bottlenecks automatically")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 3. Wait for automatic data collection
    print("3. Waiting 60 seconds for automatic data collection...")
    print("   (The profiler automatically captures memory snapshots every 5 seconds)")
    time.sleep(60)
    
    # 4. Check memory hotspots (automatically discovered)
    print("4. Getting automatically discovered memory hotspots...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/hotspots")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Found {len(data['hotspots'])} memory hotspots automatically")
            
            if data['hotspots']:
                print(f"\n🔥 BIGGEST MEMORY CONSUMERS (auto-discovered):")
                for i, hotspot in enumerate(data['hotspots'][:7], 1):
                    print(f"   {i}. {hotspot['file_line']}")
                    print(f"      Memory: {hotspot['memory_mb']:.2f}MB ({hotspot['object_count']:,} objects)")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 5. Check memory growth analysis
    print("5. Getting automatic memory growth analysis...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/growth")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Analyzed {data['timespan_snapshots']} snapshots for growth patterns")
            
            if data['growth_analysis']:
                print(f"\n📈 MEMORY GROWTH DETECTED (automatic analysis):")
                for growth in data['growth_analysis'][:5]:
                    if growth['memory_growth_mb'] > 0.1:  # Show significant growth
                        print(f"   📈 {growth['file_line']}")
                        print(f"      Growth: +{growth['memory_growth_mb']:.2f}MB ({growth['object_growth']:+} objects)")
            else:
                print("   ℹ️ No significant memory growth detected")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 6. Stop automatic profiling and get final report
    print("6. Stopping automatic profiling and getting comprehensive report...")
    try:
        response = requests.get(f"{BASE_URL}/api/system/memory/stop-auto-profiling")
        if response.status_code == 200:
            data = response.json()
            print("✅ Automatic profiling stopped")
            
            if 'final_report' in data:
                report = data['final_report']
                print(f"\n📊 COMPREHENSIVE MEMORY ANALYSIS:")
                print(f"   Final memory: {report['memory_mb']:.2f}MB")
                print(f"   CPU usage: {report['cpu_percent']:.1f}%")
                print(f"   Total snapshots analyzed: {report['snapshots_count']}")
                
                if report.get('endpoint_stats'):
                    print(f"\n🎯 API ENDPOINT MEMORY USAGE:")
                    endpoints = report['endpoint_stats']
                    # Sort by total memory usage
                    sorted_endpoints = sorted(endpoints.items(), 
                                            key=lambda x: x[1]['total_memory'], reverse=True)
                    for endpoint, stats in sorted_endpoints[:5]:
                        avg_memory = stats['total_memory'] / max(stats['calls'], 1)
                        print(f"   • {endpoint}: {stats['calls']} calls, "
                              f"avg {avg_memory:.2f}MB, max {stats['max_memory']:.2f}MB")
        else:
            print(f"❌ Failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    print()
    
    # 7. Force cleanup
    print("7. Testing memory cleanup...")
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
    
    print("\n🎯 AUTOMATIC Memory profiler test complete!")
    print("\n📋 What you now have:")
    print("✅ Automatic discovery of ALL memory-consuming code")
    print("✅ No need to guess where problems are")
    print("✅ Real-time hotspot detection")
    print("✅ Memory growth analysis over time")
    print("✅ Per-endpoint memory usage statistics")
    print("\n🔍 Available endpoints:")
    print("- /api/system/memory - Real-time memory status + hotspots")
    print("- /api/system/memory/start-auto-profiling - Begin automatic tracking")
    print("- /api/system/memory/hotspots - Current memory hotspots")
    print("- /api/system/memory/growth - Memory growth analysis")
    print("- /api/system/memory/cleanup - Force garbage collection")

if __name__ == "__main__":
    test_automatic_memory_profiler()

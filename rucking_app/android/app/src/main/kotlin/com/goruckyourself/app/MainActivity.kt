package com.goruckyourself.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "com.getrucky.app/background_location"
    private val HEART_RATE_CHANNEL = "com.getrucky.gfy/heartRateStream"
    private val WATCH_SESSION_CHANNEL = "com.getrucky.gfy/watch_session"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Background location channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    startLocationService()
                    result.success(null)
                }
                "stopTracking" -> {
                    stopLocationService()
                    result.success(null)
                }
                "isTracking" -> {
                    val isActive = isLocationServiceActive()
                    result.success(isActive)
                }
                "acquireWakeLock" -> {
                    // Manual WakeLock acquisition handled in service
                    result.success(null)
                }
                "releaseWakeLock" -> {
                    // Manual WakeLock release handled in service
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Watch session channel - stub implementation to prevent crashes
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_SESSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startWorkout", "sendMessage", "pingWatch" -> {
                    // Android doesn't support Watch connectivity, return false/null
                    result.success(false)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Heart rate event channel - stub implementation to prevent crashes
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HEART_RATE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Android doesn't support Watch heart rate streaming
                    // Just don't send any events - this prevents the crash
                    // The Flutter side should handle the lack of data gracefully
                }
                
                override fun onCancel(arguments: Any?) {
                    // No-op for Android
                }
            }
        )
    }
    
    private fun startLocationService() {
        val intent = Intent(this, LocationTrackingService::class.java)
        intent.action = LocationTrackingService.ACTION_START_TRACKING
        startForegroundService(intent)
    }
    
    private fun stopLocationService() {
        val intent = Intent(this, LocationTrackingService::class.java)
        intent.action = LocationTrackingService.ACTION_STOP_TRACKING
        startService(intent)
    }
    
    private fun isLocationServiceActive(): Boolean {
        val prefs = getSharedPreferences("RuckingApp", MODE_PRIVATE)
        return prefs.getBoolean("has_active_session", false)
    }
}

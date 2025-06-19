package com.goruckyourself.app

import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "com.getrucky.app/background_location"
    private val HEART_RATE_CHANNEL = "com.getrucky.gfy/heartRateStream"
    private val WATCH_SESSION_CHANNEL = "com.getrucky.gfy/watch_session"
    
    // Track stream state to prevent cancellation errors
    private var heartRateEventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Background location channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    if (hasRequiredPermissions()) {
                        startLocationService()
                        result.success(null)
                    } else {
                        result.error("PERMISSION_DENIED", "Location permissions not granted", null)
                    }
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
        
        // Heart rate event channel - improved implementation to prevent crashes
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HEART_RATE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Track the event sink to know if stream is active
                    heartRateEventSink = events
                    // Android doesn't support Watch heart rate streaming
                    // Just track the stream state but don't send events
                }
                
                override fun onCancel(arguments: Any?) {
                    // Only clear if we have an active stream
                    if (heartRateEventSink != null) {
                        heartRateEventSink = null
                    }
                }
            }
        )
    }
    
    private fun hasRequiredPermissions(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseLocation = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        
        // For Android 14+ (API 34+), also check for FOREGROUND_SERVICE_LOCATION
        var foregroundServiceLocation = true
        if (Build.VERSION.SDK_INT >= 34) {
            foregroundServiceLocation = ContextCompat.checkSelfPermission(this, Manifest.permission.FOREGROUND_SERVICE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
        
        return (fineLocation || coarseLocation) && foregroundServiceLocation
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

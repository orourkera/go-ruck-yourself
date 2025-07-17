package com.ruck.app

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
    
    private val CHANNEL = "com.ruck.app/background_location"
    private val HEART_RATE_CHANNEL = "com.ruck.app/heartRateStream"
    private val WATCH_SESSION_CHANNEL = "com.ruck.app/watch_session"
    
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
        
        // Location permission is required (either fine or coarse)
        val hasLocationPermission = fineLocation || coarseLocation
        
        // Log the permission status for debugging
        android.util.Log.d("MainActivity", "Permission check - Fine Location: $fineLocation, Coarse Location: $coarseLocation")
        
        // For Android 14+ (API 34+), FOREGROUND_SERVICE_LOCATION should be automatically granted
        // if declared in manifest and app has valid use case (fitness apps automatically qualify)
        if (Build.VERSION.SDK_INT >= 34) {
            val foregroundServiceLocation = ContextCompat.checkSelfPermission(this, Manifest.permission.FOREGROUND_SERVICE_LOCATION) == PackageManager.PERMISSION_GRANTED
            android.util.Log.d("MainActivity", "FOREGROUND_SERVICE_LOCATION permission: $foregroundServiceLocation")
            
            // Only require location permissions - FOREGROUND_SERVICE_LOCATION should be auto-granted
            return hasLocationPermission
        }
        
        return hasLocationPermission
    }
    
    private fun startLocationService() {
        try {
            val intent = Intent(this, LocationTrackingService::class.java)
            intent.action = LocationTrackingService.ACTION_START_TRACKING
            
            android.util.Log.d("MainActivity", "Starting foreground location service")
            startForegroundService(intent)
            android.util.Log.d("MainActivity", "Foreground location service started successfully")
        } catch (e: SecurityException) {
            android.util.Log.e("MainActivity", "SecurityException starting location service: ${e.message}", e)
            // Could be permission issue or app not in eligible state
            throw e
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Unexpected error starting location service: ${e.message}", e)
            throw e
        }
    }
    
    private fun stopLocationService() {
        try {
            val intent = Intent(this, LocationTrackingService::class.java)
            intent.action = LocationTrackingService.ACTION_STOP_TRACKING
            
            // Check if we can start the service (app must be in foreground)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0+ background service restrictions
                try {
                    startService(intent)
                    android.util.Log.d("MainActivity", "Stop tracking service started successfully")
                } catch (e: IllegalStateException) {
                    android.util.Log.w("MainActivity", "Cannot start stop service in background, stopping directly")
                    // Fallback: stop service directly
                    stopService(intent)
                }
            } else {
                // Pre-Android 8.0 - no restrictions
                startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error stopping location service: ${e.message}", e)
            // Fallback: try to stop service directly
            try {
                val intent = Intent(this, LocationTrackingService::class.java)
                stopService(intent)
            } catch (fallbackError: Exception) {
                android.util.Log.e("MainActivity", "Fallback stop service also failed: ${fallbackError.message}", fallbackError)
            }
        }
    }
    
    private fun isLocationServiceActive(): Boolean {
        val prefs = getSharedPreferences("RuckingApp", MODE_PRIVATE)
        return prefs.getBoolean("has_active_session", false)
    }
}

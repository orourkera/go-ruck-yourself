package com.ruck.app

import android.content.Intent
import android.content.pm.PackageManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.net.Uri
import android.os.Bundle
import android.Manifest
import android.os.Build
import android.util.Log
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "com.ruck.app/background_location"
    private val HEART_RATE_CHANNEL = "com.ruck.app/heartRateStream"
    private val WATCH_SESSION_CHANNEL = "com.ruck.app/watch_session"
    private val GPX_IMPORT_CHANNEL = "com.ruck.app/gpx_import"
    private val BAROMETER_CHANNEL = "com.ruck.app/barometerStream"
    private val PEDOMETER_CHANNEL = "com.getrucky.gfy/pedometerStream"
    
    companion object {
        private const val TAG = "MainActivity"
        private const val STORAGE_PERMISSION_REQUEST_CODE = 100
    }
    
    // GPX file import receiver
    private val gpxImportReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d(TAG, "GPX import broadcast received: ${intent?.action}")
            
            when (intent?.action) {
                "com.ruck.app.FILE_IMPORTED" -> {
                    val action = intent.getStringExtra("action")
                    val fileName = intent.getStringExtra("fileName")
                    
                    Log.d(TAG, "File imported: $action - $fileName")
                    
                    // Notify Flutter about the imported file
                    notifyFlutterAboutImport(action ?: "unknown", fileName ?: "")
                }
            }
        }
    }
    
    // Track stream state to prevent cancellation errors
    private var heartRateEventSink: EventChannel.EventSink? = null
    private var barometerEventSink: EventChannel.EventSink? = null
    private var pedometerStreamHandler: PedometerStreamHandler? = null
    
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
                "startPedometerSession" -> {
                    // Start a new pedometer session for real-time step tracking
                    Log.d(TAG, "Starting new pedometer session")
                    PedometerStreamHandler.startNewSession()
                    result.success(true)
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
        
        // Barometer event channel for pressure sensor streaming
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BAROMETER_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    barometerEventSink = events
                    startBarometerStreaming()
                }
                
                override fun onCancel(arguments: Any?) {
                    stopBarometerStreaming()
                    barometerEventSink = null
                }
            }
        )
        
        // Pedometer event channel for real-time step counting
        pedometerStreamHandler = PedometerStreamHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PEDOMETER_CHANNEL).setStreamHandler(pedometerStreamHandler)
        Log.d(TAG, "Pedometer event channel registered")
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
    
    // MARK: - Lifecycle Methods
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Register broadcast receiver for GPX imports
        val filter = IntentFilter("com.ruck.app.FILE_IMPORTED")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(gpxImportReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(gpxImportReceiver, filter)
        }
        
        // Handle incoming GPX files or URLs
        handleIncomingIntent(intent)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Unregister broadcast receiver
        try {
            unregisterReceiver(gpxImportReceiver)
        } catch (e: IllegalArgumentException) {
            // Receiver was not registered
            Log.w(TAG, "GPX import receiver was not registered")
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        
        // Handle new GPX files or URLs
        handleIncomingIntent(intent)
    }
    
    // MARK: - GPX Intent Handling
    private fun handleIncomingIntent(intent: Intent?) {
        Log.d(TAG, "Handling incoming intent: ${intent?.action}")
        
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                // Handle shared files/URLs
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                
                if (uri != null) {
                    Log.d(TAG, "Received shared file: $uri")
                    handleSharedFile(uri)
                } else if (text != null) {
                    Log.d(TAG, "Received shared text: $text")
                    handleSharedText(text)
                }
            }
            Intent.ACTION_VIEW -> {
                // Handle file opens and URLs
                val uri = intent.data
                if (uri != null) {
                    Log.d(TAG, "Received view intent: $uri")
                    handleFileOpen(uri)
                }
            }
            "com.ruck.app.IMPORT_GPX" -> {
                // Custom deep link for GPX imports
                val fileName = intent.getStringExtra("fileName")
                if (fileName != null) {
                    Log.d(TAG, "Deep link GPX import: $fileName")
                    notifyFlutterAboutImport("deep_link", fileName)
                }
            }
        }
    }
    
    private fun handleSharedFile(uri: Uri) {
        // Delegate to FileShareReceiver
        val intent = Intent("com.ruck.app.HANDLE_SHARED_FILE")
        intent.putExtra("uri", uri.toString())
        sendBroadcast(intent)
    }
    
    private fun handleSharedText(text: String) {
        // Delegate to FileShareReceiver
        val intent = Intent("com.ruck.app.HANDLE_SHARED_TEXT")
        intent.putExtra("text", text)
        sendBroadcast(intent)
    }
    
    private fun handleFileOpen(uri: Uri) {
        // Delegate to FileShareReceiver
        val intent = Intent("com.ruck.app.HANDLE_FILE_OPEN")
        intent.putExtra("uri", uri.toString())
        sendBroadcast(intent)
    }
    
    // MARK: - Flutter Communication
    private fun notifyFlutterAboutImport(action: String, fileName: String) {
        Log.d(TAG, "Notifying Flutter about import: $action - $fileName")
        
        // Send to Flutter through method channel
        val data = mapOf(
            "action" to action,
            "fileName" to fileName,
            "timestamp" to System.currentTimeMillis()
        )
        
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, GPX_IMPORT_CHANNEL).invokeMethod("fileImported", data)
        }
    }
    
    // MARK: - Permission Helpers
    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) 
                != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(
                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                    STORAGE_PERMISSION_REQUEST_CODE
                )
            }
        }
    }
    
    // Barometer sensor handling
    private var sensorManager: SensorManager? = null
    private var pressureSensor: Sensor? = null
    private val barometerListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            event?.let { sensorEvent ->
                if (sensorEvent.sensor.type == Sensor.TYPE_PRESSURE) {
                    val pressureMb = sensorEvent.values[0] // millibar (hPa)
                    val pressurePa = pressureMb * 100.0 // Convert to Pascals
                    
                    val barometerData = mapOf(
                        "pressure" to pressurePa,
                        "timestamp" to System.currentTimeMillis().toDouble()
                    )
                    
                    barometerEventSink?.success(barometerData)
                }
            }
        }
        
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
            Log.d(TAG, "Barometer sensor accuracy changed: $accuracy")
        }
    }
    
    private fun startBarometerStreaming() {
        try {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            pressureSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PRESSURE)
            
            if (pressureSensor == null) {
                Log.w(TAG, "Pressure sensor not available on this device")
                barometerEventSink?.error("UNAVAILABLE", "Pressure sensor not available", null)
                return
            }
            
            val success = sensorManager?.registerListener(
                barometerListener,
                pressureSensor,
                SensorManager.SENSOR_DELAY_NORMAL // ~5Hz update rate
            ) ?: false
            
            if (success) {
                Log.d(TAG, "Barometer streaming started successfully")
            } else {
                Log.e(TAG, "Failed to register barometer sensor listener")
                barometerEventSink?.error("SENSOR_ERROR", "Failed to start barometer streaming", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting barometer streaming: ${e.message}")
            barometerEventSink?.error("SENSOR_ERROR", e.message, null)
        }
    }
    
    private fun stopBarometerStreaming() {
        try {
            sensorManager?.unregisterListener(barometerListener)
            Log.d(TAG, "Barometer streaming stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping barometer streaming: ${e.message}")
        }
    }
}

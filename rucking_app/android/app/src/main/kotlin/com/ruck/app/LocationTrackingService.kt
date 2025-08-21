package com.ruck.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationResult
import android.os.Looper
import android.os.Handler

/**
 * Dedicated location tracking service for background session recording.
 * Follows FitoTrack's architecture with manual WakeLock management.
 */
class LocationTrackingService : Service() {
    
    companion object {
        const val CHANNEL_ID = "location_tracking_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START_TRACKING = "START_TRACKING"
        const val ACTION_STOP_TRACKING = "STOP_TRACKING"
        const val ACTION_RESUME_TRACKING = "RESUME_TRACKING"
    }
    
    private var wakeLock: PowerManager.WakeLock? = null
    private var isTracking = false
    
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private val cancellationTokenSource = CancellationTokenSource()
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        Log.d("LocationService", "Location tracking service created")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        
        when (action) {
            ACTION_START_TRACKING, ACTION_RESUME_TRACKING -> {
                startLocationTracking()
            }
            ACTION_STOP_TRACKING -> {
                stopLocationTracking()
            }
        }
        
        // Return START_STICKY so service restarts if killed by system
        return START_STICKY
    }
    
    private fun startLocationTracking() {
        if (isTracking) {
            Log.d("LocationService", "Already tracking, ignoring start request")
            return
        }
        
        Log.i("LocationService", "Starting location tracking...")
        
        // Acquire wake lock to prevent CPU sleep during tracking
        acquireWakeLock()
        
        // Start foreground service with proper service type
        startForegroundWithType()
        
        // Mark session as active for heartbeat monitoring
        markSessionActive(true)
        
        // Start heartbeat monitoring
        SessionHeartbeatManager.scheduleHeartbeat(this)
        
        isTracking = true
        Log.i("LocationService", "Location tracking started successfully")
    }
    
    private fun stopLocationTracking() {
        if (!isTracking) {
            Log.d("LocationService", "Not tracking, ignoring stop request")
            return
        }
        
        Log.i("LocationService", "Stopping location tracking...")
        
        // Release wake lock
        releaseWakeLock()
        
        // Mark session as inactive
        markSessionActive(false)
        
        // Cancel heartbeat monitoring
        SessionHeartbeatManager.cancelHeartbeat(this)
        
        isTracking = false
        
        // Stop foreground service
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        
        Log.i("LocationService", "Location tracking stopped")
    }
    
    private fun startForegroundWithType() {
        try {
            // Check if we have all required permissions before starting foreground service
            if (!hasRequiredPermissions()) {
                Log.e("LocationService", "Missing required permissions for foreground service")
                stopSelf()
                return
            }
            
            val notification = createNotification()
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ requires explicit foreground service type
                startForeground(
                    NOTIFICATION_ID, 
                    notification, 
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            
            Log.i("LocationService", "Foreground service started successfully")
            
        } catch (e: SecurityException) {
            Log.e("LocationService", "SecurityException starting foreground service - insufficient permissions", e)
            // Stop the service if we can't start it properly
            stopSelf()
        } catch (e: Exception) {
            Log.e("LocationService", "Failed to start foreground service", e)
            stopSelf()
        }
    }
    
    private fun hasRequiredPermissions(): Boolean {
        val hasLocationPermission = ContextCompat.checkSelfPermission(
            this, 
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED || 
        ContextCompat.checkSelfPermission(
            this, 
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        val hasForegroundServicePermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ContextCompat.checkSelfPermission(
                this, 
                android.Manifest.permission.FOREGROUND_SERVICE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Not required on older versions
        }
        
        val hasLocationForegroundServicePermission = if (Build.VERSION.SDK_INT >= 34) {
            ContextCompat.checkSelfPermission(
                this, 
                android.Manifest.permission.FOREGROUND_SERVICE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Not required on older versions
        }
        
        Log.d("LocationService", "Permission check - Location: $hasLocationPermission, ForegroundService: $hasForegroundServicePermission, LocationForegroundService: $hasLocationForegroundServicePermission")
        
        return hasLocationPermission && hasForegroundServicePermission && hasLocationForegroundServicePermission
    }
    
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "RuckingApp:LocationTracking"
            )
            // CRITICAL FIX: Extend wakelock to 12 hours for ultra-long ruck sessions
            // Guarantees CPU stays awake for 10+ hour rucks
            wakeLock?.acquire(12 * 60 * 60 * 1000L) // 12 hour timeout
            Log.d("LocationService", "WakeLock acquired for 12 hours")
        } catch (e: Exception) {
            Log.e("LocationService", "Failed to acquire WakeLock", e)
        }
    }
    
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d("LocationService", "WakeLock released")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e("LocationService", "Failed to release WakeLock", e)
        }
    }
    
    private fun markSessionActive(active: Boolean) {
        val prefs = getSharedPreferences("RuckingApp", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("has_active_session", active)
            .apply()
        Log.d("LocationService", "Session active state: $active")
    }
    
    private fun createNotification(): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Rucking in Progress")
            .setContentText("Tracking your ruck session - tap to return to app")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ruck Session Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifications for active ruck session tracking"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLock()
        markSessionActive(false)
        SessionHeartbeatManager.cancelHeartbeat(this)
        Log.d("LocationService", "Location tracking service destroyed")
    }
}

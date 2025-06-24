package com.ruck.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

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
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
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
    }
    
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "RuckingApp:LocationTracking"
            )
            wakeLock?.acquire(60 * 60 * 1000L) // 1 hour timeout as safety
            Log.d("LocationService", "WakeLock acquired")
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

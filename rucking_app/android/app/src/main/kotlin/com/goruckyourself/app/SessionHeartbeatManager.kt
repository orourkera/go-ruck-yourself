package com.goruckyourself.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Session heartbeat manager following FitoTrack's pattern.
 * Schedules periodic checks to ensure location service stays alive during active sessions.
 */
object SessionHeartbeatManager {
    
    private const val HEARTBEAT_INTERVAL_MS = 15 * 60 * 1000L // 15 minutes like FitoTrack
    internal const val HEARTBEAT_ACTION = "com.goruckyourself.app.SESSION_HEARTBEAT"
    private const val REQUEST_CODE = 1001
    
    fun scheduleHeartbeat(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, SessionHeartbeatReceiver::class.java)
        intent.action = HEARTBEAT_ACTION
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Schedule repeating alarm
        val triggerTime = System.currentTimeMillis() + HEARTBEAT_INTERVAL_MS
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
        }
        
        Log.d("SessionHeartbeat", "Scheduled heartbeat alarm for ${HEARTBEAT_INTERVAL_MS/1000/60} minutes")
    }
    
    fun cancelHeartbeat(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, SessionHeartbeatReceiver::class.java)
        intent.action = HEARTBEAT_ACTION
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        alarmManager.cancel(pendingIntent)
        Log.d("SessionHeartbeat", "Cancelled heartbeat alarm")
    }
}

/**
 * Receiver for heartbeat alarms that checks and resurrects location service if needed.
 */
class SessionHeartbeatReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == SessionHeartbeatManager.HEARTBEAT_ACTION) {
            Log.d("SessionHeartbeat", "Heartbeat alarm triggered, checking session state...")
            
            val prefs = context.getSharedPreferences("RuckingApp", Context.MODE_PRIVATE)
            val hasActiveSession = prefs.getBoolean("has_active_session", false)
            
            if (hasActiveSession) {
                // Check if location service is actually running
                val serviceRunning = isLocationServiceRunning(context)
                
                if (!serviceRunning) {
                    Log.w("SessionHeartbeat", "Active session detected but service not running, restarting...")
                    
                    // Restart the location service
                    val serviceIntent = Intent(context, LocationTrackingService::class.java)
                    serviceIntent.action = "RESUME_TRACKING"
                    context.startForegroundService(serviceIntent)
                } else {
                    Log.d("SessionHeartbeat", "Session active and service running, all good")
                }
                
                // Schedule next heartbeat
                SessionHeartbeatManager.scheduleHeartbeat(context)
            } else {
                Log.d("SessionHeartbeat", "No active session, stopping heartbeat")
                SessionHeartbeatManager.cancelHeartbeat(context)
            }
        }
    }
    
    private fun isLocationServiceRunning(context: Context): Boolean {
        // This is a simplified check - in reality you'd check ActivityManager.getRunningServices()
        // or use a more sophisticated method to detect if the foreground service is actually running
        return true // Placeholder - implement proper service detection
    }
}

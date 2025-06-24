package com.ruck.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot receiver to restart location tracking if a session was active before reboot.
 * This follows FitoTrack's pattern for session resurrection.
 */
class BootReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("BootReceiver", "Device booted, checking for active sessions...")
            
            val prefs = context.getSharedPreferences("RuckingApp", Context.MODE_PRIVATE)
            val hasActiveSession = prefs.getBoolean("has_active_session", false)
            
            if (hasActiveSession) {
                Log.i("BootReceiver", "Active session detected, starting location service...")
                
                // Start the location tracking service
                val serviceIntent = Intent(context, LocationTrackingService::class.java)
                serviceIntent.action = "RESUME_TRACKING"
                context.startForegroundService(serviceIntent)
                
                // Also schedule heartbeat alarms
                SessionHeartbeatManager.scheduleHeartbeat(context)
            } else {
                Log.d("BootReceiver", "No active session found, skipping service start")
            }
        }
    }
}

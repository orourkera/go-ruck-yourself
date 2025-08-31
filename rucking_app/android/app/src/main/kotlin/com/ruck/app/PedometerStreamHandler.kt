package com.ruck.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.*

class PedometerStreamHandler(private val context: Context) : EventChannel.StreamHandler, SensorEventListener {
    
    private var eventSink: EventChannel.EventSink? = null
    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var stepDetectorSensor: Sensor? = null
    private var isListening = false
    
    // Session tracking
    private var sessionStartTime: Long = 0
    private var sessionStartStepCount: Int = 0
    private var lastStepCount: Int = 0
    
    companion object {
        private const val TAG = "PEDOMETER"
        
        // Static methods for session management
        fun startNewSession() {
            Log.d(TAG, "🆕 New pedometer session started")
            // Session will be initialized when onListen is called
        }
        
        fun getLastStepCount(): Int {
            // Return last known step count (could be enhanced with persistent storage)
            return 0
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "🏃 Flutter listening for pedometer updates")
        eventSink = events
        isListening = true
        
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        
        // Try to use step counter sensor first (cumulative steps since boot)
        stepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        stepDetectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        
        when {
            stepCounterSensor != null -> {
                Log.d(TAG, "✅ Using TYPE_STEP_COUNTER sensor")
                sensorManager?.registerListener(this, stepCounterSensor, SensorManager.SENSOR_DELAY_UI)
            }
            stepDetectorSensor != null -> {
                Log.d(TAG, "✅ Using TYPE_STEP_DETECTOR sensor (fallback)")
                sensorManager?.registerListener(this, stepDetectorSensor, SensorManager.SENSOR_DELAY_UI)
            }
            else -> {
                Log.e(TAG, "❌ No step sensors available on this device")
                eventSink?.error("UNAVAILABLE", "Step counting is not available on this device", null)
                return
            }
        }
        
        // Initialize session
        sessionStartTime = System.currentTimeMillis()
        sessionStartStepCount = 0 // Will be set when first sensor reading comes in
        
        Log.d(TAG, "🚀 Pedometer sensor registered and listening")
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "🛑 Flutter stopped listening for pedometer updates")
        isListening = false
        
        sensorManager?.unregisterListener(this)
        eventSink = null
        
        Log.d(TAG, "🔴 Pedometer sensor unregistered")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (!isListening || eventSink == null || event == null) {
            return
        }
        
        when (event.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> {
                // Cumulative steps since device boot
                val totalSteps = event.values[0].toInt()
                
                // Initialize session baseline on first reading
                if (sessionStartStepCount == 0) {
                    sessionStartStepCount = totalSteps
                    Log.d(TAG, "📊 Session baseline set: $sessionStartStepCount steps")
                }
                
                // Calculate steps for current session
                val sessionSteps = totalSteps - sessionStartStepCount
                lastStepCount = sessionSteps
                
                Log.d(TAG, "📊 Step Counter - Total: $totalSteps, Session: $sessionSteps")
                
                sendStepData(sessionSteps, 0.0) // Distance calculation not available on Android
            }
            
            Sensor.TYPE_STEP_DETECTOR -> {
                // Each event represents one step detected
                lastStepCount++
                
                Log.d(TAG, "📊 Step Detector - Session steps: $lastStepCount")
                
                sendStepData(lastStepCount, 0.0)
            }
        }
    }
    
    private fun sendStepData(steps: Int, distance: Double) {
        val pedometerInfo = mapOf(
            "steps" to steps,
            "distance" to distance, // Android sensors don't provide distance
            "pace" to 0.0, // Android sensors don't provide pace
            "cadence" to 0.0, // Android sensors don't provide cadence
            "timestamp" to (System.currentTimeMillis() / 1000.0)
        )
        
        eventSink?.success(pedometerInfo)
        Log.d(TAG, "✅ Sent to Flutter: $steps steps")
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        Log.d(TAG, "📊 Sensor accuracy changed: ${sensor?.name} - accuracy: $accuracy")
    }
}
import Foundation
import CoreMotion
import Flutter

class PedometerStreamHandler: NSObject, FlutterStreamHandler {
    private static var eventSink: FlutterEventSink?
    private static var pedometer: CMPedometer?
    private static var isListening = false
    private static var sessionStartDate: Date?
    private static var lastStepCount: Int = 0
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("[PEDOMETER] 🏃 Flutter listening for pedometer updates")
        PedometerStreamHandler.eventSink = events
        PedometerStreamHandler.isListening = true
        
        // Check if step counting is available
        guard CMPedometer.isStepCountingAvailable() else {
            print("[PEDOMETER] ❌ Step counting not available on this device")
            return FlutterError(code: "UNAVAILABLE", 
                              message: "Step counting is not available on this device", 
                              details: nil)
        }
        
        // Check if we have motion authorization
        if #available(iOS 11.0, *) {
            let status = CMPedometer.authorizationStatus()
            print("[PEDOMETER] Authorization status: \(status.rawValue)")
            if status == .denied || status == .restricted {
                print("[PEDOMETER] ❌ Motion & Fitness permission denied")
                return FlutterError(code: "PERMISSION_DENIED",
                                  message: "Motion & Fitness permission is required",
                                  details: "Please enable Motion & Fitness in Settings")
            }
        }
        
        // Initialize pedometer if needed
        if PedometerStreamHandler.pedometer == nil {
            PedometerStreamHandler.pedometer = CMPedometer()
            print("[PEDOMETER] ✅ CMPedometer initialized")
        }
        
        // Start from session beginning or current time
        let startDate = PedometerStreamHandler.sessionStartDate ?? Date()
        PedometerStreamHandler.sessionStartDate = startDate
        
        print("[PEDOMETER] 🚀 Starting pedometer updates from: \(startDate)")
        
        // Start receiving live pedometer updates
        PedometerStreamHandler.pedometer?.startUpdates(from: startDate) { pedometerData, error in
            guard PedometerStreamHandler.isListening else {
                print("[PEDOMETER] Not listening anymore, ignoring update")
                return
            }
            
            if let error = error {
                print("[PEDOMETER] ❌ Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    if let sink = PedometerStreamHandler.eventSink {
                        // Don't send error to Flutter, just log it and continue
                        // Some errors are temporary (like device locked)
                        print("[PEDOMETER] Suppressing error to maintain stream")
                    }
                }
                return
            }
            
            if let data = pedometerData {
                let steps = data.numberOfSteps.intValue
                let distance = data.distance?.doubleValue ?? 0.0
                let pace = data.currentPace?.doubleValue
                let cadence = data.currentCadence?.doubleValue
                
                print("[PEDOMETER] 📊 Update - Steps: \(steps), Distance: \(distance)m, Pace: \(pace ?? 0), Cadence: \(cadence ?? 0)")
                
                // Store last known count
                PedometerStreamHandler.lastStepCount = steps
                
                // Send data to Flutter
                let pedometerInfo: [String: Any] = [
                    "steps": steps,
                    "distance": distance,
                    "pace": pace ?? 0,
                    "cadence": cadence ?? 0,
                    "timestamp": Date().timeIntervalSince1970
                ]
                
                DispatchQueue.main.async {
                    if PedometerStreamHandler.isListening, 
                       let sink = PedometerStreamHandler.eventSink {
                        sink(pedometerInfo)
                        print("[PEDOMETER] ✅ Sent to Flutter: \(steps) steps")
                    }
                }
            }
        }
        
        // Also query for current total to get immediate value
        PedometerStreamHandler.pedometer?.queryPedometerData(from: startDate, to: Date()) { pedometerData, error in
            if let data = pedometerData {
                let steps = data.numberOfSteps.intValue
                print("[PEDOMETER] 📊 Initial query - Steps: \(steps)")
                
                let pedometerInfo: [String: Any] = [
                    "steps": steps,
                    "distance": data.distance?.doubleValue ?? 0.0,
                    "pace": 0,
                    "cadence": 0,
                    "timestamp": Date().timeIntervalSince1970
                ]
                
                DispatchQueue.main.async {
                    if PedometerStreamHandler.isListening,
                       let sink = PedometerStreamHandler.eventSink {
                        sink(pedometerInfo)
                    }
                }
            }
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("[PEDOMETER] 🛑 Flutter stopped listening for pedometer updates")
        PedometerStreamHandler.isListening = false
        
        // Stop pedometer updates
        PedometerStreamHandler.pedometer?.stopUpdates()
        
        // Clear event sink after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !PedometerStreamHandler.isListening {
                PedometerStreamHandler.eventSink = nil
            }
        }
        
        return nil
    }
    
    // Static method to reset session start time
    static func startNewSession() {
        sessionStartDate = Date()
        lastStepCount = 0
        print("[PEDOMETER] 🆕 New session started at: \(sessionStartDate!)")
    }
    
    // Static method to get last known step count
    static func getLastStepCount() -> Int {
        return lastStepCount
    }
}
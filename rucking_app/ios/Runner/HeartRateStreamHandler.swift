import Foundation
import Flutter

// Stream handler for heart rate EventChannel
class HeartRateStreamHandler: NSObject, FlutterStreamHandler {
    private static var eventSink: FlutterEventSink?
    static var lastHeartRateSent: Double?
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        print("[HR_STREAM] Flutter listening for heart rate updates")
        HeartRateStreamHandler.eventSink = eventSink
        
        // Send last known heart rate if available
        if let lastHR = HeartRateStreamHandler.lastHeartRateSent {
            print("[HR_STREAM] Sending buffered heart rate: \(lastHR)")
            eventSink(lastHR)
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("[HR_STREAM] Flutter stopped listening for heart rate updates")
        HeartRateStreamHandler.eventSink = nil
        return nil
    }
    
    static func sendHeartRate(_ heartRate: Double) {
        print("[HR_STREAM] Attempting to send heart rate: \(heartRate) BPM")
        lastHeartRateSent = heartRate
        
        DispatchQueue.main.async {
            if let sink = eventSink {
                print("[HR_STREAM] ✅ Sending heart rate to Flutter: \(heartRate)")
                sink(heartRate)
            } else {
                print("[HR_STREAM] ⚠️ No event sink available - buffering heart rate")
            }
        }
    }
}
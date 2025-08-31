import Foundation
import Flutter

// Stream handler for step count EventChannel
class StepCountStreamHandler: NSObject, FlutterStreamHandler {
    private static var eventSink: FlutterEventSink?
    static var lastStepCountSent: Int?
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        print("[STEP_STREAM] Flutter listening for step count updates")
        StepCountStreamHandler.eventSink = eventSink
        
        // Send last known step count if available
        if let lastSteps = StepCountStreamHandler.lastStepCountSent {
            print("[STEP_STREAM] Sending buffered step count: \(lastSteps)")
            eventSink(lastSteps)
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("[STEP_STREAM] Flutter stopped listening for step count updates")
        StepCountStreamHandler.eventSink = nil
        return nil
    }
    
    static func sendStepCount(_ steps: Int) {
        print("[STEP_STREAM] Attempting to send step count: \(steps) steps")
        lastStepCountSent = steps
        
        DispatchQueue.main.async {
            if let sink = eventSink {
                print("[STEP_STREAM] ✅ Sending step count to Flutter: \(steps)")
                sink(steps)
            } else {
                print("[STEP_STREAM] ⚠️ No event sink available - buffering step count")
            }
        }
    }
}
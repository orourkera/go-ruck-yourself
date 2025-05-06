import UIKit
import Flutter
import WatchConnectivity

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
    
    private var session: WCSession?
    private let methodChannelName = "com.yourcompany.ruckingapp/watch"
    private let eventChannelName = "com.yourcompany.ruckingapp/heartRateStream"
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Setup WatchConnectivity
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        
        // Setup Flutter Method Channel for communication with Dart
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: controller.binaryMessenger)
        
        methodChannel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }
            
            switch call.method {
            case "startWorkout":
                self.sendMessageToWatch(["command": "workoutStarted"])
                result(true)
            case "stopWorkout":
                self.sendMessageToWatch(["command": "workoutStopped"])
                result(true)
            case "updateMetrics":
                if let metrics = call.arguments as? [String: Any] {
                    self.sendMessageToWatch(["command": "updateMetrics", "metrics": metrics])
                    result(true)
                } else {
                    result(FlutterError(code: "-1", message: "Invalid arguments", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        
        // Setup Flutter Event Channel for streaming heart rate data to Dart
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: controller.binaryMessenger)
        eventChannel.setStreamHandler(HeartRateStreamHandler())
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Send message to Watch
    private func sendMessageToWatch(_ message: [String: Any]) {
        guard let session = session, session.isActivated, session.isReachable else {
            print("Watch session is not connected.")
            return
        }
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending message to Watch: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WCSessionDelegate Methods
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Watch session activation failed: \(error.localizedDescription)")
            return
        }
        print("Watch session activated with state: \(activationState.rawValue)")
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("Watch session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("Watch session deactivated")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle messages from Watch, such as heart rate data
        if let heartRate = message["heartRate"] as? Double {
            HeartRateStreamHandler.sendHeartRate(heartRate)
        }
    }
}

// Stream handler for heart rate data to Flutter
class HeartRateStreamHandler: NSObject, FlutterStreamHandler {
    private static var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        HeartRateStreamHandler.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        HeartRateStreamHandler.eventSink = nil
        return nil
    }
    
    static func sendHeartRate(_ heartRate: Double) {
        eventSink?(heartRate)
    }
}

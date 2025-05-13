import UIKit
import Flutter
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
    
    private var session: WCSession?
    private let watchSessionChannelName = "com.getrucky.gfy/watch_session"
    private let watchHealthChannelName = "com.getrucky.gfy/watch_health"
    private let userPrefsChannelName = "com.getrucky.gfy/user_preferences"
    private let eventChannelName = "com.getrucky.gfy/heartRateStream"
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Setup WatchConnectivity
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            if session?.activationState != .activated {
                session?.activate()
            }
        }
        
        // Setup Flutter Method Channels for communication with Dart
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        
        // Watch Session Channel
        let watchSessionChannel = FlutterMethodChannel(name: watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
        
        watchSessionChannel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }
            print("[WATCH] Received method call: \(call.method)")
            
            switch call.method {
            case "sendMessage":
                if let messageData = call.arguments as? [String: Any] {
                    print("[WATCH] Sending message to watch: \(messageData)")
                    self.sendMessageToWatch(messageData)
                    result(true)
                } else {
                    result(FlutterError(code: "-1", message: "Invalid arguments", details: nil))
                }
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
                print("[WATCH] Method not implemented: \(call.method)")
                result(FlutterMethodNotImplemented)
            }
        })
        
        // Watch Health Channel
        let watchHealthChannel = FlutterMethodChannel(name: watchHealthChannelName, binaryMessenger: controller.binaryMessenger)
        
        watchHealthChannel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }
            print("[WATCH_HEALTH] Received method call: \(call.method)")
            
            switch call.method {
            case "getHeartRate":
                // Implement heart rate retrieval if needed
                result(nil)
            default:
                print("[WATCH_HEALTH] Method not implemented: \(call.method)")
                result(FlutterMethodNotImplemented)
            }
        })
        
        // User Preferences Channel
        let userPrefsChannel = FlutterMethodChannel(name: userPrefsChannelName, binaryMessenger: controller.binaryMessenger)
        
        userPrefsChannel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }
            print("[USER_PREFS] Received method call: \(call.method)")
            
            switch call.method {
            case "getUserWeight":
                // Implement user weight retrieval if needed
                result(70.0) // Default value
            default:
                print("[USER_PREFS] Method not implemented: \(call.method)")
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
        guard let session = session else {
            print("[WATCH] Watch session is nil.")
            return
        }
        
        // Log the current activation state
        let stateString: String
        switch session.activationState {
        case .notActivated: stateString = "Not Activated"
        case .inactive: stateString = "Inactive"
        case .activated: stateString = "Activated"
        @unknown default: stateString = "Unknown"
        }
        
        print("[WATCH] Current session state: \(stateString)")
        print("[WATCH] Is watch reachable: \(session.isReachable)")
        print("[WATCH] Is paired: \(session.isPaired)")
        print("[WATCH] Is complication enabled: \(session.isComplicationEnabled)")
        
        // Try to send even if not activated as a test
        if session.isReachable {
            print("[WATCH] Sending message to watch: \(message)")
            session.sendMessage(message, replyHandler: { reply in
                print("[WATCH] Watch replied: \(reply)")
            }) { error in
                print("[WATCH] Error sending message to Watch: \(error.localizedDescription)")
                
                // Try application context as fallback
                do {
                    try session.updateApplicationContext(message)
                    print("[WATCH] Updated application context after send error")
                } catch {
                    print("[WATCH] Failed to update context after send error: \(error.localizedDescription)")
                }
            }
        } else {
            print("[WATCH] Watch is not reachable. Trying alternative methods.")
            
            // Try to transfer as application context as fallback
            do {
                try session.updateApplicationContext(message)
                print("[WATCH] Updated application context instead")
            } catch {
                print("[WATCH] Failed to update application context: \(error.localizedDescription)")
            }
            
            // Try transferUserInfo as another option
            session.transferUserInfo(message)
            print("[WATCH] Attempted transferUserInfo as fallback")
        }
    }
    
    // MARK: - WCSessionDelegate Methods
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WATCH] Watch session activation failed: \(error.localizedDescription)")
            return
        }
        print("[WATCH] Watch session activated with state: \(activationState.rawValue)")
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WATCH] Watch session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("[WATCH] Watch session deactivated")
        // Reactivate session if possible
        session.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("[WATCH] Received message from Watch: \(message)")
        
        // Handle messages from Watch, such as heart rate data
        if let heartRate = message["heartRate"] as? Double {
            print("[WATCH] Received heart rate: \(heartRate) BPM")
            HeartRateStreamHandler.sendHeartRate(heartRate)
        }
        
        // Handle other message types as needed
        if let command = message["command"] as? String {
            print("[WATCH] Received command from Watch: \(command)")
            
            switch command {
            case "sessionStarted":
                // Handle session started on Watch
                break
            case "sessionEnded":
                // Handle session ended on Watch
                break
            case "sessionPaused":
                // Handle session paused on Watch
                break
            case "sessionResumed":
                // Handle session resumed on Watch
                break
            default:
                print("[WATCH] Unknown command: \(command)")
            }
        }
    }
    
    // Handle application context updates from Watch
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("[WATCH] Received application context from Watch: \(applicationContext)")
        
        // Process the context similarly to messages
        if let heartRate = applicationContext["heartRate"] as? Double {
            print("[WATCH] Received heart rate from context: \(heartRate) BPM")
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

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
                // Use auto-launch functionality
                self.launchWatchAppAndStartSession(["command": "workoutStarted"])
                result(true)
            case "stopWorkout":
                self.sendMessageToWatch(["command": "workoutStopped"])
                result(true)
            case "watchHeartRateUpdate":
                // Handle heart rate update from Flutter
                if let heartRate = call.arguments as? [String: Any], let heartRateValue = heartRate["heartRate"] as? Double {
                    print("[WATCH] Manually processing watchHeartRateUpdate with heartRate: \(heartRateValue)")
                    // Also trigger heart rate stream to ensure Flutter receives this
                    HeartRateStreamHandler.sendHeartRate(heartRateValue)
                }
                result(true)
            case "updateMetrics":
                if let metrics = call.arguments as? [String: Any] {
                    // Create a copy of metrics where we can add additional data
                    var enhancedMetrics = metrics
                    
                    // Make sure session state (paused status) is always included in enhanced metrics
                    // This ensures the watch always has the latest state from the iPhone
                    if let isPaused = metrics["isPaused"] as? Bool {
                        // If isPaused is already in the metrics, make sure it's in integer format as expected by watch
                        enhancedMetrics["isPaused"] = isPaused ? 1 : 0
                    }
                    
                    self.sendMessageToWatch(["command": "updateMetrics", "metrics": enhancedMetrics])
                    result(true)
                } else {
                    result(FlutterError(code: "-1", message: "Invalid arguments", details: nil))
                }
                
            case "updateSessionState":
                if let stateData = call.arguments as? [String: Any], let isPaused = stateData["isPaused"] as? Bool {
                    print("[WATCH] Sending session state update to watch: isPaused = \(isPaused)")
                    self.sendMessageToWatch(["command": "updateSessionState", "isPaused": isPaused])
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
    
    /// Send a message to the watch via the session channel
    private func sendMessageToWatch(_ message: [String: Any], launchApp: Bool = false) {
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
            
            // Always use transferUserInfo since this works even when watch app is not running
            var userInfo = message
            if launchApp {
                print("[WATCH] Setting launchApp flag to auto-launch Watch app")
            }
            session.transferUserInfo(userInfo)
            print("[WATCH] Attempted transferUserInfo\(launchApp ? " with auto-launch flag" : "")")
        }
    }
    
    // Launch the watch app and start session
    private func launchWatchAppAndStartSession(_ message: [String: Any]) {
        guard let session = session else {
            print("[WATCH] Watch session is nil.")
            return
        }
        
        // Set message content
        var userInfo = message
        if !userInfo.keys.contains("command") {
            userInfo["command"] = "workoutStarted"
        }
        
        // Use both methods to ensure message is delivered
        // 1. Standard message sending if watch is reachable
        sendMessageToWatch(userInfo, launchApp: true)
        
        // 2. Specifically use transferUserInfo which works for app launch
        print("[WATCH] Attempting to auto-launch Watch app with session")
        session.transferUserInfo(userInfo)
        
        // 3. For devices supporting WKApplication launch
        if #available(iOS 16.0, *) {
            print("[WATCH] Using modern WKApplication launch API")
            session.transferCurrentComplicationUserInfo(userInfo)
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
    }
    
    // Receive and process messages from the Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        processWatchMessage(message: message, replyHandler: nil)
    }
    
    // Receive and process messages from the Watch that require a reply
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        processWatchMessage(message: message, replyHandler: replyHandler)
    }
    
    // Common processing function for both message types
    private func processWatchMessage(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        // Handle message commands
        if let command = message["command"] as? String {
            print("[WATCH] Received command from Watch: \(command)")
            
            // Get controller and channel only once
            let controller = window?.rootViewController as! FlutterViewController
            let watchSessionChannel = FlutterMethodChannel(name: watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
            
            switch command {
            case "sessionStarted":
                print("[WATCH] Session started from Watch")
            case "sessionEnded":
                print("[WATCH] Session ended from Watch")
            case "pauseSession":
                print("[WATCH] Session pause command received from Watch - forwarding to Flutter")
                watchSessionChannel.invokeMethod("onWatchSessionUpdated", arguments: ["action": "pauseSession"]) { result in
                    if let error = result as? FlutterError {
                        print("[WATCH] Error forwarding pause command to Flutter: \(error.message ?? "unknown error")")
                        // Send error back if reply handler exists
                        replyHandler?(["error": error.message ?? "unknown error"])
                    } else {
                        print("[WATCH] Successfully forwarded pause command to Flutter")
                        // Use reply handler if available, otherwise send a regular message
                        if let replyHandler = replyHandler {
                            replyHandler(["status": "success", "command": "pauseConfirmed"])
                        } else {
                            self.sendMessageToWatch(["command": "pauseConfirmed"])
                        }
                    }
                }
            case "resumeSession":
                print("[WATCH] Session resume command received from Watch - forwarding to Flutter")
                watchSessionChannel.invokeMethod("onWatchSessionUpdated", arguments: ["action": "resumeSession"]) { result in
                    if let error = result as? FlutterError {
                        print("[WATCH] Error forwarding resume command to Flutter: \(error.message ?? "unknown error")")
                        // Send error back if reply handler exists
                        replyHandler?(["error": error.message ?? "unknown error"])
                    } else {
                        print("[WATCH] Successfully forwarded resume command to Flutter")
                        if let replyHandler = replyHandler {
                            replyHandler(["status": "success", "command": "resumeConfirmed"])
                        } else {
                            self.sendMessageToWatch(["command": "resumeConfirmed"])
                        }
                    }
                }
            case "watchHeartRateUpdate":
                if let heartRate = message["heartRate"] as? Double {
                    print("[WATCH] Heart rate update command received: \(heartRate) BPM")
                    HeartRateStreamHandler.sendHeartRate(heartRate)
                    
                    // Acknowledge the heart rate reception if reply handler is available
                    replyHandler?(["status": "success", "heartRateReceived": heartRate])
                }
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

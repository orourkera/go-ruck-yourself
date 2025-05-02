import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate, FlutterRuckingApi {

    // Define the method channel names (must match Flutter side)
    let SESSION_CHANNEL_NAME = "com.getrucky.gfy/watch_session"
    let HEALTH_CHANNEL_NAME = "com.getrucky.gfy/watch_health"
    // We might need USER_PREFS_CHANNEL_NAME too if sending prefs TO watch

    var sessionChannel: FlutterMethodChannel?
    var healthChannel: FlutterMethodChannel?
    var session: WCSession?

    private func cleanDictionary(_ dict: [String: Any]) -> [String: Any] {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            if let cleaned = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                return cleaned
            }
        } catch {
            print("Error cleaning dictionary: \(error)")
        }
        return dict
    }
    
    // New helper to encode dictionary as JSON string
    private func dictionaryToJsonString(_ dict: [String: Any]) -> String? {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error encoding dictionary to JSON string: \(error)")
            return nil
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Get the FlutterViewController and BinaryMessenger
        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("rootViewController is not type FlutterViewController")
        }
        let binaryMessenger = controller.binaryMessenger

        // Set up Flutter Method Channels (Watch -> Flutter)
        sessionChannel = FlutterMethodChannel(name: SESSION_CHANNEL_NAME, binaryMessenger: binaryMessenger)
        healthChannel = FlutterMethodChannel(name: HEALTH_CHANNEL_NAME, binaryMessenger: binaryMessenger)
        print("Method Channels Established (Watch -> Flutter)")
        
        // ** Set up Pigeon HostApi (Flutter -> Watch) **
        FlutterRuckingApiSetup.setUp(binaryMessenger: binaryMessenger, api: self)
        print("Pigeon Host API Setup (Flutter -> Watch)")

        // Set up Watch Connectivity
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("WCSession activated")
        } else {
            print("WCSession not supported on this device")
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - WCSessionDelegate Methods

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        print("iOS WCSession activated with state: \(activationState.rawValue)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession did become inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession did deactivate")
        session.activate()
    }

    // Helper function to process received data (from message or userInfo)
    private func handleReceivedData(_ data: [String: Any], isReplyExpected: Bool = false, replyHandler: (([String : Any]) -> Void)? = nil) {
        print("---> [AppDelegate] handleReceivedData called with: \(data)")

        guard let command = data["command"] as? String else {
            print("---> [AppDelegate] Invalid data format: Missing command")
            if isReplyExpected { replyHandler?(["status": "error", "message": "Missing command"]) }
            return
        }
        print("---> [AppDelegate] Parsed command: \(command)")

        // Ensure Flutter channel calls happen on the main thread
        DispatchQueue.main.async {
            print("---> [AppDelegate] Executing on main thread for command: \(command)")
            
            // Prepare arguments for Flutter - structure might vary by command
            var flutterArgs: [String: Any]? = data // Start with the received data
            flutterArgs?.removeValue(forKey: "command") // Remove command key itself

            switch command {
            // --- Session Actions ---    
            case "startSession":
                print("[AppDelegate] Handling session update: startSession")
                guard let ruckWeight = data["ruckWeight"] as? Double else {
                    print("[AppDelegate] Missing ruckWeight in startSession message")
                    return
                }
                let sessionData: [String: Any] = ["action": "startSession", "ruckWeight": ruckWeight]
                if let sessionJSONString = self.dictionaryToJsonString(sessionData) {
                    print("[AppDelegate] Prepared session JSON string: \(sessionJSONString)")
                    self.sessionChannel?.invokeMethod("onWatchSessionUpdated", arguments: sessionJSONString) { result in
                        print("[AppDelegate] Invoked 'onWatchSessionUpdated' with result: \(result ?? "No result")")
                    }
                    print("[AppDelegate] Attempting to invoke 'onWatchSessionUpdated' on sessionChannel...")
                } else {
                    print("[AppDelegate] Failed to convert session data to JSON string")
                }
            case "pauseSession":
                print("[AppDelegate] Handling session update: pauseSession")
                let sessionData: [String: Any] = ["action": "pauseSession"]
                if let sessionJSONString = self.dictionaryToJsonString(sessionData) {
                    print("[AppDelegate] Prepared session JSON string: \(sessionJSONString)")
                    self.sessionChannel?.invokeMethod("onWatchSessionUpdated", arguments: sessionJSONString) { result in
                        print("[AppDelegate] Invoked 'onWatchSessionUpdated' with result: \(result ?? "No result")")
                    }
                    print("[AppDelegate] Attempting to invoke 'onWatchSessionUpdated' on sessionChannel...")
                } else {
                    print("[AppDelegate] Failed to convert session data to JSON string")
                }
            case "resumeSession":
                print("[AppDelegate] Handling session update: resumeSession")
                let sessionData: [String: Any] = ["action": "resumeSession"]
                if let sessionJSONString = self.dictionaryToJsonString(sessionData) {
                    print("[AppDelegate] Prepared session JSON string: \(sessionJSONString)")
                    self.sessionChannel?.invokeMethod("onWatchSessionUpdated", arguments: sessionJSONString) { result in
                        print("[AppDelegate] Invoked 'onWatchSessionUpdated' with result: \(result ?? "No result")")
                    }
                    print("[AppDelegate] Attempting to invoke 'onWatchSessionUpdated' on sessionChannel...")
                } else {
                    print("[AppDelegate] Failed to convert session data to JSON string")
                }
            case "endSession":
                print("[AppDelegate] Handling session update: endSession")
                let sessionData: [String: Any] = ["action": "endSession"]
                if let sessionJSONString = self.dictionaryToJsonString(sessionData) {
                    print("[AppDelegate] Prepared session JSON string: \(sessionJSONString)")
                    self.sessionChannel?.invokeMethod("onWatchSessionUpdated", arguments: sessionJSONString) { result in
                        print("[AppDelegate] Invoked 'onWatchSessionUpdated' with result: \(result ?? "No result")")
                    }
                    print("[AppDelegate] Attempting to invoke 'onWatchSessionUpdated' on sessionChannel...")
                } else {
                    print("[AppDelegate] Failed to convert session data to JSON string")
                }
            // --- Health Updates ---    
            case "updateHeartRate": // Add other health commands like updateDistance if needed
                print("---> [AppDelegate] Handling health update: \(command)")
                // Structure arguments for onWatchHealthUpdated - expects a map
                // Let's assume Flutter expects something like {'type': 'heartRate', 'value': 89}
                var healthPayload: [String: Any]? = nil
                let heartRateValue = data["heartRate"]
                print("---> [AppDelegate] Raw heartRate value: \(heartRateValue ?? "nil"), Type: \(type(of: heartRateValue)))")

                if command == "updateHeartRate" {
                    if let rate = heartRateValue as? Double {
                        print("---> [AppDelegate] Casting heartRate directly to Double.")
                        healthPayload = ["type": "heartRate", "value": rate]
                    } else if let nsRate = heartRateValue as? NSNumber {
                        print("---> [AppDelegate] Casting heartRate from NSNumber to Double.")
                        healthPayload = ["type": "heartRate", "value": nsRate.doubleValue]
                    } else {
                        print("---> [AppDelegate] WARN: Could not cast heartRate to Double or NSNumber.")
                    }
                }
                 // Add other health types here...
                
                if let payload = healthPayload {
                    // Encode as JSON string to avoid type issues
                    if let jsonString = self.dictionaryToJsonString(payload) {
                        print("---> [AppDelegate] Prepared health JSON string: \(jsonString)")
                        print("---> [AppDelegate] Attempting to invoke 'onHealthDataUpdated' on healthChannel...")
                        self.healthChannel?.invokeMethod("onHealthDataUpdated", arguments: jsonString) { result in
                            if let error = result as? FlutterError {
                                print("---> [AppDelegate] Error invoking Flutter method 'onHealthDataUpdated': \(error.message ?? "Unknown Flutter Error")")
                            } // No reply needed for health updates typically
                            if isReplyExpected { replyHandler?(["status": "success"]) } // Still acknowledge if reply was expected
                        }
                    } else {
                        print("---> [AppDelegate] Failed to encode health args to JSON")
                        if isReplyExpected { replyHandler?(["status": "error", "message": "JSON encoding failed for health update"]) }
                    }
                } else {
                    print("---> [AppDelegate] Could not prepare payload for health update: \(command)")
                    if isReplyExpected { replyHandler?(["status": "error", "message": "Missing data for healthUpdate: \(command)"]) }
                }

            // --- Other Commands ---    
            case "requestInitialState":
                 print("---> [AppDelegate] Watch requested initial state (Not fully implemented)")
                 let currentState = ["isSessionActive": false] // Placeholder
                 if isReplyExpected { replyHandler?(["status": "success", "data": currentState]) }
            
             // case "userPreferences": // Example if needed later
             //     print("---> [AppDelegate] Handling 'userPreferences'...")
             //     // Forward flutterArgs to appropriate channel/method
             //     if isReplyExpected { replyHandler?(["status": "success"]) }

            default:
                 print("---> [AppDelegate] Unknown command received: \(command)")
                 if isReplyExpected { replyHandler?(["status": "error", "message": "Unknown command"]) }
            }
        }
    }

    // Handles messages sent WITH a replyHandler
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handleReceivedData(message, isReplyExpected: true, replyHandler: replyHandler)
    }

    // Handles messages sent WITHOUT a replyHandler (e.g., replyHandler: nil from Watch)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleReceivedData(message, isReplyExpected: false, replyHandler: nil)
    }

    // Handles data sent via transferUserInfo (NO reply handler)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Note: UserInfo transfers might contain system keys like WCSessionUserInfoTransferKey
        // Filter out non-app data if necessary, or adjust handleReceivedData
        print("---> [AppDelegate] session:didReceiveUserInfo called with: \(userInfo)")
        handleReceivedData(userInfo, isReplyExpected: false, replyHandler: nil)
    }
    
    // MARK: - FlutterRuckingApi Implementation (Flutter -> Native)
    
    func updateSessionOnWatch(distance: Double, duration: Double, pace: Double, isPaused: Bool) throws {
        print("[AppDelegate/Pigeon] updateSessionOnWatch called - Distance: \(distance), Duration: \(duration), Pace: \(pace), Paused: \(isPaused)")
        let message: [String: Any] = [
            "command": "updateSession",
            "distance": distance,
            "duration": duration,
            "pace": pace,
            "isPaused": isPaused
        ]
        sendMessageToWatch(message)
    }
    
    func startSessionOnWatch(ruckWeight: Double) throws {
         print("[AppDelegate/Pigeon] startSessionOnWatch called - Ruck Weight: \(ruckWeight)")
         let message: [String: Any] = [
             "command": "startSession",
             "ruckWeight": ruckWeight
         ]
         sendMessageToWatch(message)
    }

    func pauseSessionOnWatch() throws {
        if WCSession.default.isReachable {
            print("Watch is reachable. Sending pause command.")
            let message = ["command": "pauseSession"]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("Error sending pause message: \(error.localizedDescription)")
            }
            print("Pause message queued successfully.")
        } else {
            print("Watch not reachable for pausing.")
        }
    }

    func resumeSessionOnWatch() throws {
        if WCSession.default.isReachable {
            print("Watch is reachable. Sending resume command.")
            let message = ["command": "resumeSession"]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("Error sending resume message: \(error.localizedDescription)")
            }
            print("Resume message queued successfully.")
        } else {
            print("Watch not reachable for resuming.")
        }
    }

    func endSessionOnWatch() throws {
        if WCSession.default.isReachable {
             print("Watch is reachable. Sending end command.")
            let message = ["command": "endSession"]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                 print("Error sending end message: \(error.localizedDescription)")
            }
            print("End message queued successfully.")
        } else {
            print("Watch not reachable for ending.")
        }
    }
    
    // Helper to send message to Watch
    private func sendMessageToWatch(_ message: [String: Any]) {
        guard let session = self.session, session.isReachable else {
            print("[AppDelegate] Watch not reachable, can't send message: \(message)")
            // Optionally handle queuing or error feedback to Flutter
            return
        }
        
        session.sendMessage(message, replyHandler: { reply in
            print("[AppDelegate] Received reply from watch: \(reply)")
            // Handle reply if needed
        }, errorHandler: { error in
            print("[AppDelegate] Error sending message to watch: \(error.localizedDescription)")
            // Handle error if needed
        })
    }
}

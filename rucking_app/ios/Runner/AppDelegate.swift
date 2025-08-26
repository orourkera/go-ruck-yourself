import UIKit
import Flutter
import WatchConnectivity
import UserNotifications
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
    
    private var session: WCSession?
    private let watchSessionChannelName = "com.getrucky.gfy/watch_session"
    private let watchHealthChannelName = "com.getrucky.gfy/watch_health"
    private let userPrefsChannelName = "com.getrucky.gfy/user_preferences"
    private let eventChannelName = "com.getrucky.gfy/heartRateStream"
    private let stepEventChannelName = "com.getrucky.gfy/stepStream"
    private let queuedMessagesKey = "WCQueuedMessages"
    
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
        
        // Setup Firebase
        FirebaseApp.configure()
        
        // Register plugins first so custom channels bind to the final binary messenger
        GeneratedPluginRegistrant.register(with: self)
        
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
            case "flutterHeartRateListenerReady":
                // Flutter heart rate listener is ready
                // If we have buffered heart rates in HeartRateStreamHandler, now is the time to send them
                if let lastHR = HeartRateStreamHandler.lastHeartRateSent {
                    // Re-sending most recent heart rate
                    HeartRateStreamHandler.sendHeartRate(lastHR)
                }
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
                    print("[WATCH] Sending session state update to watch: isPaused = \(isPaused ? 1 : 0) (as Int)")
                    self.sendMessageToWatch(["command": "updateSessionState", "isPaused": isPaused ? 1 : 0])
                    result(true)
                } else {
                    result(FlutterError(code: "-1", message: "Invalid arguments", details: nil))
                }
            case "getQueuedWatchMessages":
                // Return and clear any queued WCSession userInfo messages collected while Flutter wasn't ready
                let queued = self.dequeueAllQueuedMessages()
                result(queued)
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
        
        // Setup Flutter Event Channel for streaming step count data to Dart
        let stepEventChannel = FlutterEventChannel(name: stepEventChannelName, binaryMessenger: controller.binaryMessenger)
        stepEventChannel.setStreamHandler(StepCountStreamHandler())
        
        // Register for push notifications and get APNS token
        if #available(iOS 10.0, *) {
            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization(
                options: authOptions,
                completionHandler: { granted, error in
                    print("Push notification permission granted: \(granted)")
                    if let error = error {
                        print("Push notification permission error: \(error)")
                    }
                }
            )
        } else {
            let settings: UIUserNotificationSettings =
                UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }
        
        // Register for remote notifications to get APNS token
        application.registerForRemoteNotifications()
        
        // Re-assert our AppDelegate as the WCSession delegate AFTER all plugins
        // (including Firebase via GeneratedPluginRegistrant) have initialized.
        // This prevents Firebase's GUL_Runner.AppDelegate from hijacking WCSession calls.
        if WCSession.isSupported() {
            session = WCSession.default // Ensure session is not nil if it wasn't already set up
            session?.delegate = self
            // Activate if not already active (might be redundant but safe)
            if session?.activationState != .activated {
                session?.activate()
            }
            // Start a watchdog timer that re-asserts the delegate every 10 seconds in case another
            // library tries to hijack it while the app is running.
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                guard let self else { return }
                let defaultSession = WCSession.default
                if !(defaultSession.delegate === self) {
                    print("[WATCH] Watchdog: delegate hijacked (\(String(describing: defaultSession.delegate))). Re-asserting AppDelegate as delegate.")
                    defaultSession.delegate = self
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Ensure WCSession delegate remains set when app becomes active (protect against delegate hijacking)
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        if WCSession.isSupported() {
            let defaultSession = WCSession.default
            if !(defaultSession.delegate === self) {
                print("[WATCH] Detected delegate hijack (\(String(describing: defaultSession.delegate))). Re-asserting AppDelegate as WCSession delegate.")
                defaultSession.delegate = self
            }
        }
    }
    
    /// Send a message to the watch via the session channel
    private func sendMessageToWatch(_ message: [String: Any], launchApp: Bool = false) {
        guard let session = session else {
            print("[WATCH] Watch session is nil.")
            return
        }
        
        // Send the message: live when reachable, context/queued otherwise
        if session.isReachable {
            print("[WATCH] sendMessageToWatch: live send → \(message)")
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WATCH] Live send failed (\(error.localizedDescription)); falling back to applicationContext")
                do {
                    try session.updateApplicationContext(message)
                } catch {
                    print("[WATCH] updateApplicationContext fallback failed: \(error.localizedDescription)")
                }
            }
        } else {
            print("[WATCH] sendMessageToWatch: watch not reachable – using applicationContext\(launchApp ? " + transferUserInfo" : "")")
            do {
                try session.updateApplicationContext(message)
            } catch {
                print("[WATCH] updateApplicationContext failed: \(error.localizedDescription)")
            }
            // Only queue with transferUserInfo when explicitly requested (e.g., auto-launch)
            if launchApp {
                session.transferUserInfo(message)
            }
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
        DispatchQueue.main.async {
            print("[WATCH] Watch session activated with state: \(activationState.rawValue)")
            if let error = error {
                print("[WATCH] Activation error: \(error.localizedDescription)")
            }
            // You might want to inform Flutter or update UI based on activationState
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            print("[WATCH] Watch session did become inactive")
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            print("[WATCH] Watch session did deactivate. Re-activating...")
            session.activate() // Re-activate the session
        }
    }

    // Receive and process messages from the Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("[WATCH] Received message from Watch (raw): \(message)")
        DispatchQueue.main.async {
            print("[WATCH] Processing message on main thread: \(message)")
            self.processWatchMessage(message: message, replyHandler: nil)
        }
    }

    // Receive and process messages from the Watch that require a reply
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("[WATCH] Received message from Watch (raw): \(message)")
        DispatchQueue.main.async {
            print("[WATCH] Processing message on main thread: \(message)")
            self.processWatchMessage(message: message, replyHandler: replyHandler)
        }
    }

    // Common processing function for both message types
    private func processWatchMessage(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        // Handle message commands
        if let command = message["command"] as? String {
            print("[WATCH] Received command: \(command)")

            switch command {
            case "startSessionFromWatch":
                // Background-safe: create and start session using REST when Flutter not ready
                // Expect optional fields: ruckWeight (Double), startedAt (epoch seconds), tempId (String)
                let ruckWeight = (message["ruckWeight"] as? Double) ?? 10.0
                let tempId = (message["tempId"] as? String) ?? UUID().uuidString
                // Defer to Flutter when UI is present; otherwise make a minimal REST call if you have a direct client here.
                if let controller = self.window?.rootViewController as? FlutterViewController {
                    let chan = FlutterMethodChannel(name: self.watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
                    chan.invokeMethod("onWatchSessionUpdated", arguments: [
                        "command": "startSession",
                        "ruckWeight": ruckWeight,
                        "tempId": tempId
                    ]) { _ in }
                } else {
                    // Queue for Flutter to process on next launch
                    self.enqueueMessage(["command": "startSession", "ruckWeight": ruckWeight, "tempId": tempId])
                }
                replyHandler?(["status": "accepted", "tempId": tempId])
            case "sessionStarted":
                print("[WATCH] Session started from Watch")
            case "sessionEnded":
                print("[WATCH] Session ended from Watch")
            case "pauseSession":
                print("[DEBUG] Session pause command received from Watch - forwarding to Flutter")
                let controller = window?.rootViewController as! FlutterViewController
                let watchSessionChannel = FlutterMethodChannel(name: watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
                watchSessionChannel.invokeMethod("onWatchSessionUpdated", arguments: ["command": "pauseSession"] as [String: Any]) { result in
                    if let error = result as? FlutterError {
                        print("[ERROR] Error forwarding pause command to Flutter: \(error.message ?? "unknown error")")
                        // Send error back if reply handler exists
                        replyHandler?(["error": error.message ?? "unknown error"])
                    } else {
                        print("[DEBUG] Successfully forwarded pause command to Flutter")
                        // Use reply handler if available, otherwise send a regular message
                        if let replyHandler = replyHandler {
                            replyHandler(["status": "success", "command": "pauseConfirmed"])
                        } else {
                            self.sendMessageToWatch(["command": "pauseConfirmed"])
                        }
                    }
                }
            case "resumeSession":
                print("[DEBUG] Session resume command received from Watch - forwarding to Flutter")
                let controller = window?.rootViewController as! FlutterViewController
                let watchSessionChannel = FlutterMethodChannel(name: watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
                watchSessionChannel.invokeMethod("onWatchSessionUpdated", arguments: ["command": "resumeSession"] as [String: Any]) { result in
                    if let error = result as? FlutterError {
                        print("[ERROR] Error forwarding resume command to Flutter: \(error.message ?? "unknown error")")
                        // Send error back if reply handler exists
                        replyHandler?(["error": error.message ?? "unknown error"])
                    } else {
                        print("[DEBUG] Successfully forwarded resume command to Flutter")
                        // Use reply handler if available, otherwise send a regular message
                        if let replyHandler = replyHandler {
                            replyHandler(["status": "success", "command": "resumeConfirmed"])
                        } else {
                            self.sendMessageToWatch(["command": "resumeConfirmed"])
                        }
                    }
                }
            case "endSession":
                print("[DEBUG] Session end command received from Watch - forwarding to Flutter")
                let controller = window?.rootViewController as! FlutterViewController
                let watchSessionChannel = FlutterMethodChannel(name: watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
                watchSessionChannel.invokeMethod("onWatchSessionUpdated", arguments: ["command": "endSession"] as [String: Any]) { result in
                    if let error = result as? FlutterError {
                        print("[ERROR] Error forwarding end command to Flutter: \(error.message ?? "unknown error")")
                        replyHandler?(["error": error.message ?? "unknown error"])
                    } else {
                        print("[DEBUG] Successfully forwarded end command to Flutter")
                        if let replyHandler = replyHandler {
                            replyHandler(["status": "success", "command": "sessionEnded"])
                        } else {
                            // Notify watch that phone accepted end request
                            self.sendMessageToWatch(["command": "sessionEnded"]) // also handled by watch cleanup switch
                        }
                    }
                }
            case "debug_watchEndTapped":
                // Optional: log-only debug signal from watch to confirm tap
                print("[DEBUG] Received debug_watchEndTapped from Watch")
            case "watchHeartRateUpdate":
                if let heartRate = message["heartRate"] as? Double {
                    // Heart rate update received
                    HeartRateStreamHandler.sendHeartRate(heartRate)
                    
                    // Acknowledge the heart rate reception if reply handler is available
                    replyHandler?(["status": "success", "heartRateReceived": heartRate])
                }
            case "watchStepUpdate":
                if let steps = message["steps"] as? Int {
                    print("[WATCH] Step update received: \(steps) steps")
                    // Forward step update to Flutter via EventChannel
                    StepCountStreamHandler.sendStepCount(steps)
                    
                    // Acknowledge the step reception if reply handler is available
                    replyHandler?(["status": "success", "stepsReceived": steps])
                }
            default:
                print("[WATCH] Unknown command: \(command)")
                replyHandler?(["status": "error", "message": "Unknown command \(command)"])
            }
        } else {
            print("[WATCH] Received message from Watch without a valid 'command' string (or 'command' was not a string): \(message)")
            replyHandler?(["status": "error", "message": "Message did not contain a valid command string"])
        }
    }

    // Queue WCSession userInfo for later delivery to Flutter if Flutter is not yet ready
    private func enqueueMessage(_ message: [String: Any]) {
        var list = UserDefaults.standard.array(forKey: queuedMessagesKey) as? [[String: Any]] ?? []
        list.append(message)
        UserDefaults.standard.set(list, forKey: queuedMessagesKey)
    }
    private func dequeueAllQueuedMessages() -> [[String: Any]] {
        let list = UserDefaults.standard.array(forKey: queuedMessagesKey) as? [[String: Any]] ?? []
        UserDefaults.standard.removeObject(forKey: queuedMessagesKey)
        return list
    }

    // Handle application context updates from Watch
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("[WATCH] Received application context from Watch (raw): \(applicationContext)")
        DispatchQueue.main.async {
            print("[WATCH] Processing application context on main thread: \(applicationContext)")
            self.processWatchMessage(message: applicationContext, replyHandler: nil) // No reply handler for context updates
        }
    }

    // Handle userInfo transfers (background-queued messages)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        print("[WATCH] Received userInfo from Watch: \(userInfo)")
        DispatchQueue.main.async {
            // If we have a Flutter engine ready, forward immediately; otherwise queue
            if let controller = self.window?.rootViewController as? FlutterViewController {
                // Heart rate batches
                if let type = userInfo["type"] as? String, type == "hr_sample" {
                    if let bpm = userInfo["bpm"] as? Double {
                        HeartRateStreamHandler.sendHeartRate(bpm)
                    }
                }
                // Command-based messages
                if let _ = userInfo["command"] as? String {
                    let watchSessionChannel = FlutterMethodChannel(name: self.watchSessionChannelName, binaryMessenger: controller.binaryMessenger)
                    watchSessionChannel.invokeMethod("onWatchSessionUpdated", arguments: userInfo) { _ in }
                } else {
                    // Queue unknown payloads for Flutter to query later
                    self.enqueueMessage(userInfo)
                }
            } else {
                // No Flutter controller – queue for later retrieval
                self.enqueueMessage(userInfo)
            }
        }
    }
    
    // MARK: - APNS Token Handling
    
    override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("APNS token received: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
        return super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
}

// Stream handler for step count data to Flutter
class StepCountStreamHandler: NSObject, FlutterStreamHandler {
    private static var eventSink: FlutterEventSink?
    private static var lastErrorLogTime: Date?
    private static var lastStepCountSent: Int?
    private static var lastStepCountSentTime: Date?
    private static var pendingStepCounts: [Int] = []
    private static var isListening: Bool = false
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("🟢 [WATCH] StepCountStreamHandler.onListen called - setting up event sink")
        StepCountStreamHandler.eventSink = events
        StepCountStreamHandler.isListening = true
        
        // Send any pending step counts that were buffered while sink was unavailable
        if !StepCountStreamHandler.pendingStepCounts.isEmpty {
            let countsToSend = StepCountStreamHandler.pendingStepCounts
            StepCountStreamHandler.pendingStepCounts.removeAll()
            
            for (index, count) in countsToSend.enumerated() {
                let delay = Double(index) * 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if StepCountStreamHandler.isListening, let sink = StepCountStreamHandler.eventSink {
                        sink(count)
                    }
                }
            }
        }
        
        // If we have a recent step count, send it immediately
        if let lastCount = StepCountStreamHandler.lastStepCountSent,
           let lastTime = StepCountStreamHandler.lastStepCountSentTime,
           Date().timeIntervalSince(lastTime) < 60 {
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if StepCountStreamHandler.isListening {
                    events(lastCount)
                }
            }
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("🔴 [WATCH] StepCountStreamHandler.onCancel called - removing event sink")
        StepCountStreamHandler.isListening = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if !StepCountStreamHandler.isListening {
                print("🔴 [WATCH] Clearing step count event sink after delay")
                StepCountStreamHandler.eventSink = nil
            }
        }
        return nil
    }
    
    static func sendStepCount(_ stepCount: Int) {
        lastStepCountSent = stepCount
        lastStepCountSentTime = Date()
        
        print("[WATCH] Processing step count: \(stepCount)")
        
        if Thread.isMainThread {
            sendStepCountOnMainThread(stepCount)
        } else {
            DispatchQueue.main.async {
                sendStepCountOnMainThread(stepCount)
            }
        }
    }
    
    private static func sendStepCountOnMainThread(_ stepCount: Int) {
        if isListening, let sink = eventSink {
            print("[WATCH] Sending step count to Flutter: \(stepCount)")
            let message = [
                "command": "watchStepUpdate",
                "steps": stepCount
            ] as [String: Any]
            sink(message)
            
            pendingStepCounts.removeAll { $0 == stepCount }
        } else {
            if !pendingStepCounts.contains(stepCount) {
                pendingStepCounts.append(stepCount)
                if pendingStepCounts.count > 50 {
                    pendingStepCounts.removeFirst()
                }
            }
            
            let now = Date()
            if lastErrorLogTime == nil || now.timeIntervalSince(lastErrorLogTime!) > 10 {
                print("❌ [WATCH] ERROR: Cannot send step count to Flutter - eventSink is nil")
                lastErrorLogTime = now
            }
        }
    }
}

// Stream handler for heart rate data to Flutter
class HeartRateStreamHandler: NSObject, FlutterStreamHandler {
    // Use static eventSink so it persists across instance lifecycle
    private static var eventSink: FlutterEventSink?
    
    // Flag to track if we've logged error about event sink recently
    private static var lastErrorLogTime: Date?
    static var lastHeartRateSent: Double?
    static var lastHeartRateSentTime: Date?
    
    // Buffer for heart rates received when sink is unavailable
    private static var pendingHeartRates: [Double] = []
    
    // Flag to track if we're actively listening
    private static var isListening: Bool = false
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("🟢 [WATCH] HeartRateStreamHandler.onListen called - setting up event sink")
        HeartRateStreamHandler.eventSink = events
        HeartRateStreamHandler.isListening = true
        
        // Send any pending heart rates that were buffered while sink was unavailable
        if !HeartRateStreamHandler.pendingHeartRates.isEmpty {
            // Sending buffered heart rates
            // Make a copy to avoid concurrent modification issues
            let ratesToSend = HeartRateStreamHandler.pendingHeartRates
            HeartRateStreamHandler.pendingHeartRates.removeAll()
            
            // Send buffered rates with small delays to ensure they're processed
            for (index, rate) in ratesToSend.enumerated() {
                let delay = Double(index) * 0.1 // 100ms between each to avoid overwhelming
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Only send if we still have an active sink
                    if HeartRateStreamHandler.isListening, let sink = HeartRateStreamHandler.eventSink {
                        // Sending buffered heart rate
                        sink(rate)
                    }
                }
            }
        }
        
        // If we have a recent heart rate, send it immediately to ensure the UI updates
        if let lastHR = HeartRateStreamHandler.lastHeartRateSent,
           let lastTime = HeartRateStreamHandler.lastHeartRateSentTime,
           Date().timeIntervalSince(lastTime) < 60 { // Only if within last minute
            
            // Re-sending cached heart rate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if HeartRateStreamHandler.isListening {
                    events(lastHR) // Send to the new listener after a short delay
                }
            }
        }
        
        // Notify Flutter that we're ready for heart rate updates
        NotificationCenter.default.post(name: NSNotification.Name("HeartRateChannelReady"), object: nil)
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("🔴 [WATCH] HeartRateStreamHandler.onCancel called - removing event sink")
        HeartRateStreamHandler.isListening = false
        // Don't immediately set eventSink to nil - keep a reference in case we need it
        // We'll use the isListening flag to determine if we should actually send data
        
        // Schedule clearing the eventSink after a delay to allow for Flutter hot reload
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            // Only clear if we're still not listening after the delay
            if !HeartRateStreamHandler.isListening {
                print("🔴 [WATCH] Clearing event sink after delay")
                HeartRateStreamHandler.eventSink = nil
            }
        }
        return nil
    }
    
    static func sendHeartRate(_ heartRate: Double) {
        // Store the most recent heart rate regardless of sink availability
        lastHeartRateSent = heartRate
        lastHeartRateSentTime = Date()
        
        // Force heart rate to be a whole number to match expected format
        let roundedHeartRate = round(heartRate)
        
        // Processing heart rate
        
        if Thread.isMainThread {
            sendHeartRateOnMainThread(roundedHeartRate)
        } else {
            DispatchQueue.main.async {
                sendHeartRateOnMainThread(roundedHeartRate)
            }
        }
    }
    
    private static func sendHeartRateOnMainThread(_ heartRate: Double) {
        if isListening, let sink = eventSink {
            // Sending heart rate to Flutter as a properly formatted message
            let message = [
                "command": "watchHeartRateUpdate",
                "heartRate": heartRate
            ] as [String: Any]
            sink(message)
            // Heart rate sent to Flutter
            
            // Clear successful send from pending buffer if it was there
            pendingHeartRates.removeAll { $0 == heartRate }
        } else {
            // Buffer the heart rate for later delivery when sink is available again
            if !pendingHeartRates.contains(heartRate) {
                pendingHeartRates.append(heartRate)
                // Cap the buffer size to avoid memory issues
                if pendingHeartRates.count > 50 {
                    pendingHeartRates.removeFirst()
                }
                // Buffered heart rate
            }
            
            logEventSinkError()
            // Try to recreate event channel - this is a more aggressive fix
            recreateEventChannelIfNeeded()
        }
    }
    
    private static func logEventSinkError() {
        // Only log error every 10 seconds to avoid log spam
        let now = Date()
        if lastErrorLogTime == nil || now.timeIntervalSince(lastErrorLogTime!) > 10 {
            print("❌ [WATCH] ERROR: Cannot send heart rate to Flutter - eventSink is nil. This means Flutter is not receiving heart rate updates!")
            lastErrorLogTime = now
        }
    }
    
    private static func recreateEventChannelIfNeeded() {
        // Only attempt recreation if we're not actively listening and we haven't tried recently
        guard !isListening else { return }
        
        if let lastRecreateTime = lastErrorLogTime, Date().timeIntervalSince(lastRecreateTime) < 15 {
            return // Don't try more often than every 15 seconds
        }
        
        // Actually implement the recreation logic
        // Attempting to recreate heart rate event channel
        
        // Get access to the root view controller - try both windows approach for different iOS versions
        var rootViewController: FlutterViewController? = nil
        
        // iOS 13+ approach
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let viewController = window.rootViewController as? FlutterViewController {
                rootViewController = viewController
            }
        }
        
        // Fallback for older iOS versions
        if rootViewController == nil, let window = UIApplication.shared.delegate?.window,
           let windowObj = window,
           let viewController = windowObj.rootViewController as? FlutterViewController {
            rootViewController = viewController
        }
        
        // Try a different approach if still nil
        if rootViewController == nil,
           let viewController = UIApplication.shared.windows.first?.rootViewController as? FlutterViewController {
            rootViewController = viewController
        }
        
        guard let controller = rootViewController else {
            print("❌ [WATCH] Cannot recreate event channel - no FlutterViewController available")
            return
        }
        
        // Update last attempt time
        lastErrorLogTime = Date()
        
        // Create a new event channel
        let channelName = "com.getrucky.gfy/heartRateStream"
        let eventChannel = FlutterEventChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
        
        // Important: Create a completely fresh handler instance
        let handler = HeartRateStreamHandler()
        eventChannel.setStreamHandler(handler)
        
        // Heart rate event channel recreated
        
        // Try to notify Flutter that a channel was recreated
        NotificationCenter.default.post(name: NSNotification.Name("HeartRateChannelRecreated"), object: nil)
        
        // After recreation, try to resend any buffered heart rates
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // First check if the recreation actually resulted in an active sink
            if isListening, let _ = eventSink, !pendingHeartRates.isEmpty {
                // Attempting to send buffered heart rates after recreation
                // Send the most recent heart rate immediately
                if let lastRate = pendingHeartRates.last {
                    sendHeartRate(lastRate)
                }
            } else if let lastHR = lastHeartRateSent {
                // Just try to send the last known heart rate
                sendHeartRate(lastHR)
            }
        }
    }
}

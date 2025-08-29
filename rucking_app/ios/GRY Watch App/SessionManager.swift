#if os(watchOS)
import Foundation
import WatchConnectivity
import HealthKit
import WatchKit  // Added for WKInterfaceDevice vibration

// Make protocol publicly accessible
public protocol SessionManagerDelegate: AnyObject {
    func sessionDidActivate()
    func sessionDidDeactivate()
    func didReceiveMessage(_ message: [String: Any])
}

@MainActor
public class SessionManager: NSObject, ObservableObject, WCSessionDelegate, WorkoutManagerDelegate {
    // WorkoutManager for HealthKit access
    private var workoutManager: WorkoutManager!
    // Published properties for SwiftUI
    @Published var status: String = "--"
    @Published var heartRate: Double = 0.0
    @Published var calories: Double = 0.0
    @Published var elevationGain: Double = 0.0
    @Published var elevationLoss: Double = 0.0
    @Published var distanceValue: Double = 0.0
    @Published var paceValue: Double = 0.0
    @Published var steps: Int = 0
    @Published var isPaused: Bool = false
    @Published var isSessionActive: Bool = false
    @Published var currentZone: String? = nil
    private var sessionStartedFromPhone = false // Track if session was initiated by phone
    
    // Steps monitoring debug state
    private var lastStepsUpdateAt: Date? = nil
    private var stepsWatchdogTimer: Timer? = nil
    
    // Split notification properties
    @Published var showingSplitNotification: Bool = false
    @Published var splitDistance: String = ""
    @Published var splitTime: String = ""
    @Published var totalDistance: String = ""
    @Published var totalTime: String = ""
    @Published var splitCalories: String = ""
    @Published var splitElevation: String = ""
    
    // Published user's metric preference (true = metric, false = imperial)
    @Published var isMetric: Bool = true
    @Published var lastRuckWeightKg: Double = 10.0
    @Published var lastUserWeightKg: Double = 80.0
    
    var statusText: String {
        // Status now contains the timer
        status
    }
    var heartRateText: String {
        heartRate > 0 ? "\(Int(heartRate))" : "--"
    }
    var caloriesText: String {
        calories > 0 ? "\(Int(calories))" : "--"
    }
    var stepsText: String {
        steps > 0 ? "\(steps)" : "--"
    }
    var elevationText: String {
        if elevationGain <= 0 {
            return "--"
        }
        
        // Convert to feet if using imperial units
        if !self.isMetric {
            let gainFeet = Int(elevationGain * 3.28084)
            return "+\(gainFeet) ft"
        } else {
            return "+\(Int(elevationGain)) m"
        }
    }
    var distance: String {
        if distanceValue <= 0 {
            return "--"
        }
        
        // Show miles if using imperial units, otherwise kilometers
        if !self.isMetric {
            // Convert km to miles (1 km = 0.621371 miles)
            let miles = distanceValue * 0.621371
            return String(format: "%.2f mi", miles)
        } else {
            return String(format: "%.2f km", distanceValue)
        }
    }
    var pace: String {
        if paceValue <= 0 {
            return "--"
        }
        
        // paceValue comes from Flutter in seconds per km
        var adjustedPace = paceValue
        
        // If using imperial units, convert from seconds/km to seconds/mile
        if !self.isMetric {
            // Convert from seconds per km to seconds per mile (1 mile = 1.609344 km)
            adjustedPace = paceValue * 1.609344
        }
        
        // Convert seconds to minutes:seconds format
        let minutes = Int(adjustedPace) / 60
        let seconds = Int(adjustedPace) % 60
        
        // Format as MM:SS (no unit since label will indicate it's pace)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func startSession() {
        // Start workout session (permissions already requested in init)
        workoutManager.startWorkout { error in
            if let error = error {
                print("[WATCH] Failed to start workout: \(error.localizedDescription)")
            } else {
                // Workout session started successfully
                print("[WATCH] Workout started successfully")
                
                // CRITICAL: Set session as active to show pause/stop buttons
                DispatchQueue.main.async {
                    self.isSessionActive = true
                    self.isPaused = false
                }
                
                // Only send start payload if session was initiated from watch, not phone
                // This prevents duplicate session creation when phone starts the session
                if !self.sessionStartedFromPhone {
                    let startTs = Date().timeIntervalSince1970
                    let payload: [String: Any] = [
                        "command": "startSessionFromWatch",
                        "startedAt": startTs,
                        "tempId": UUID().uuidString,
                        "ruckWeightKg": self.lastRuckWeightKg,
                        "userWeightKg": self.lastUserWeightKg
                    ]
                    self.sendMessage(payload)
                }

                // Start steps watchdog for debugging stale updates
                self.startStepsWatchdog()
            }
        }
    }

    public static let shared = SessionManager()
    weak var delegate: SessionManagerDelegate?
    private let session: WCSession
    
    override init() {
        session = WCSession.default
        // Initialize WorkoutManager after super.init()
        super.init()
        print("[WATCH BOOT] SessionManager init")
        workoutManager = WorkoutManager()
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        // Ensure we receive callbacks when the workout ends
        workoutManager.delegate = self
        
        // HealthKit permissions will be requested by InterfaceController on first launch
        print("[WATCH BOOT] SessionManager initialized - permissions will be requested by InterfaceController")
    }
    
    private func requestHealthKitPermissions() {
        print("[WATCH] Requesting HealthKit permissions...")
        
        // Set up heart rate handler
        workoutManager.setHeartRateHandler { [weak self] heartRate in
            DispatchQueue.main.async {
                self?.heartRate = heartRate
                print("[SESSION_MANAGER] Heart rate updated: \(heartRate) BPM")
                
                // Send heart rate to phone via WatchConnectivity
                self?.sendHeartRate(heartRate)
            }
        }
        
        // Set up step count handler
        workoutManager.setStepCountHandler { [weak self] stepCount in
            DispatchQueue.main.async {
                self?.steps = stepCount
                print("[SESSION_MANAGER] Steps updated: \(stepCount) steps")
                self?.lastStepsUpdateAt = Date()
                
                // Send steps to phone via WatchConnectivity
                self?.sendSteps(stepCount)
            }
        }
        
        // Check HealthKit authorization status (don't request again - already done on app launch)
        print("[WATCH] Checking existing HealthKit authorization status...")
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let stepsAuth = workoutManager.healthStore.authorizationStatus(for: stepType)
        let heartRateAuth = workoutManager.healthStore.authorizationStatus(for: heartRateType)
        
        print("[WATCH] Steps authorization: \(stepsAuth.rawValue), Heart rate authorization: \(heartRateAuth.rawValue)")
        
        if stepsAuth == .sharingAuthorized && heartRateAuth == .sharingAuthorized {
            print("[WATCH] ✅ HealthKit already authorized - proceeding with session")
            // Send success confirmation to phone
            self.sendMessage([
                "command": "healthKitPermissionGranted",
                "success": true,
                "timestamp": Date().timeIntervalSince1970
            ])
        } else {
            print("[WATCH] ❌ HealthKit not fully authorized - steps: \(stepsAuth.rawValue), heartRate: \(heartRateAuth.rawValue)")
            // Send failure notification to phone
            self.sendMessage([
                "command": "healthKitPermissionDenied",
                "success": false,
                "stepsAuth": stepsAuth.rawValue,
                "heartRateAuth": heartRateAuth.rawValue,
                "timestamp": Date().timeIntervalSince1970
            ])
        }
    }
    
    /// Set up workout handlers for heart rate and steps (called after WorkoutManager reinitialization)
    private func setupWorkoutHandlers() {
        print("[WATCH] Setting up heart rate handler...")
        workoutManager.setHeartRateHandler { [weak self] heartRate in
            DispatchQueue.main.async {
                self?.heartRate = heartRate
                print("[SESSION_MANAGER] Heart rate updated: \(heartRate) BPM")
                
                // Send heart rate to phone via WatchConnectivity
                self?.sendHeartRate(heartRate)
            }
        }
        
        print("[WATCH] Setting up step count handler...")
        workoutManager.setStepCountHandler { [weak self] stepCount in
            DispatchQueue.main.async {
                self?.steps = stepCount
                print("[SESSION_MANAGER] Steps updated: \(stepCount) steps")
                self?.lastStepsUpdateAt = Date()
                
                // Send steps to phone via WatchConnectivity
                self?.sendSteps(stepCount)
            }
        }
        
        print("[WATCH] ✅ Workout handlers configured successfully")
    }
    
    /// Check permission status without requesting (used for diagnostics)
    func checkHealthKitPermissionStatus() {
        print("[WATCH] Checking current HealthKit permission status...")
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let stepsAuth = workoutManager.healthStore.authorizationStatus(for: stepType)
        let heartRateAuth = workoutManager.healthStore.authorizationStatus(for: heartRateType)
        
        print("[WATCH] Current status - Steps: \(stepsAuth.rawValue), Heart rate: \(heartRateAuth.rawValue)")
        
        // Send status to phone
        self.sendMessage([
            "command": "healthKitStatus",
            "stepsAuth": stepsAuth.rawValue,
            "heartRateAuth": heartRateAuth.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func sendMessage(_ message: [String: Any]) {
        guard session.activationState == .activated else {
            // Queue if session isn't fully activated yet
            session.transferUserInfo(message)
            return
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WATCH] sendMessage error: \(error.localizedDescription). Falling back to transferUserInfo")
                self.session.transferUserInfo(message)
            }
        } else {
            // Not reachable - queue for delivery
            session.transferUserInfo(message)
        }
    }
    
    func sendHeartRate(_ heartRate: Double) {
        // Create a dedicated heart rate message with the command
        let message: [String: Any] = ["heartRate": heartRate, "command": "watchHeartRateUpdate"]
        
        // Send with a reply handler to confirm receipt
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(message) { reply in
                // Message sent successfully
            } errorHandler: { error in
                print("[WATCH] Failed to send heart rate: \(error.localizedDescription)")
            }
        } else {
            // Queue as user info for background delivery
            session.transferUserInfo(["type": "hr_sample", "bpm": heartRate, "timestamp": Date().timeIntervalSince1970])
        }
    }
    
    func sendSteps(_ steps: Int) {
        // Create a dedicated steps message with the command
        let message: [String: Any] = ["steps": steps, "command": "watchStepUpdate"]
        
        // Send with a reply handler to confirm receipt
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(message) { reply in
                // Message sent successfully
            } errorHandler: { error in
                print("[WATCH] Failed to send steps: \(error.localizedDescription)")
            }
        } else {
            // Queue as user info for background delivery
            session.transferUserInfo(["type": "step_sample", "steps": steps, "timestamp": Date().timeIntervalSince1970])
        }
    }
    
    // Pause the session from the watch
    func pauseSession() {
        // Emit a debug tap signal to the phone so we can confirm the watch button was pressed even
        // if the command ultimately gets ignored due to local guard conditions. This lets us see
        // evidence of the tap in the iPhone logs without needing the Watch console.
        sendMessage(["command": "debug_watchPauseTapped"])  // DEBUG ONLY – harmless for production
        
        guard isSessionActive else { 
            print("[DEBUG] Cannot pause: session not active")
            return 
        }
        
        print("[DEBUG] Pausing session from watch")
        
        // Send pause command to the iPhone app with a reply handler to confirm
        // Make sure we use a Dictionary with String keys to ensure proper mapping to Dart Map<String, dynamic>
        let message = ["command": "pauseSession"] as [String: Any]
        
        print("[DEBUG] Sending pause command to iPhone: \(message)")
        // Note: Direct Pigeon API not available in Watch extension
        // Using WatchConnectivity API instead
        
        // Fallback to WatchConnectivity API if Pigeon not available
        // Use sendMessageWithReply for acknowledgement
        if session.activationState == .activated && session.isReachable {
            // Using WatchConnectivity for pause command
            session.sendMessage(message, replyHandler: { reply in
                // Pause command acknowledged by iPhone
                // Verify state was applied correctly
                DispatchQueue.main.async {
                    // Always ensure isPaused is true when we get confirmation
                    // regardless of the current state
                    self.isPaused = true
                    print("[DEBUG] Pause confirmed by iPhone, isPaused set to true")
                }
            }, errorHandler: { error in
                print("[WATCH] Error sending pause command: \(error.localizedDescription)")
            })
        } else {
            // Fallback to regular message if not reachable
            // Using regular message channel for pause command
            sendMessage(message)
        }
        
        // Pause command sent to iPhone
    }
    
    // Toggle between pause and resume states - used by the UI button
    // We now wait for iPhone confirmation before mutating isPaused to avoid UI flicker
    func togglePauseResume() {
        print("[DEBUG] togglePauseResume tapped. Current isPaused = \(isPaused)")
        if isPaused {
            resumeSession()
        } else {
            pauseSession()
        }
    }
    
    // End the session from the watch
    func endSession() {
        // Emit a debug tap signal to the phone so we can confirm the watch button was pressed
        sendMessage(["command": "debug_watchEndTapped"])  // DEBUG ONLY
        
        guard isSessionActive else { 
            print("[DEBUG] Cannot end: session not active")
            return 
        }
        
        print("[DEBUG] Ending session from watch")
        
        // Send end command to the iPhone app
        let message = ["command": "endSession"] as [String: Any]
        
        print("[DEBUG] Sending end command to iPhone: \(message)")
        
        // Using WatchConnectivity for end command
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(message, replyHandler: { reply in
                // End command acknowledged by iPhone
                DispatchQueue.main.async {
                    self.isSessionActive = false
                    self.isPaused = false
                    print("[DEBUG] End confirmed by iPhone, session stopped")
                }
            }, errorHandler: { error in
                print("[WATCH] Error sending end command: \(error.localizedDescription)")
            })
        } else {
            // Fallback to regular message channel
            sendMessage(message)
        }
        
        // End command sent to iPhone
    }
    
    // Resume the session from the watch
    func resumeSession() {
        // Emit a debug tap signal to the phone so we can confirm the watch button was pressed.
        sendMessage(["command": "debug_watchResumeTapped"])  // DEBUG ONLY
        
        guard isSessionActive else { 
            print("[DEBUG] Cannot resume: session not active")
            return 
        }
        
        print("[DEBUG] Resuming session from watch")
        
        // Note: Direct Pigeon API not available in Watch extension
        // Using WatchConnectivity API instead
        
        // Send resume command to the iPhone app
        // Make sure we use a Dictionary with String keys to ensure proper mapping to Dart Map<String, dynamic>
        let message = ["command": "resumeSession"] as [String: Any]
        
        print("[DEBUG] Sending resume command to iPhone: \(message)")
        
        // Using WatchConnectivity for resume command
        if session.activationState == .activated && session.isReachable {
            // Use sendMessageWithReply for acknowledgement
            session.sendMessage(message, replyHandler: { reply in
                print("[DEBUG] Resume command acknowledged by iPhone: \(reply)")
            }, errorHandler: { error in
                print("[ERROR] Error sending resume command: \(error.localizedDescription)")
            })
        } else {
            // Fallback to regular message if not reachable
            sendMessage(message)
        }
        print("[DEBUG] Resume command sent to iPhone")
    }
    
    // MARK: - WCSessionDelegate
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            delegate?.sessionDidActivate()
        } else {
            delegate?.sessionDidDeactivate()
        }
        if let error = error {
            print("Session activation failed: \(error.localizedDescription)")
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        delegate?.didReceiveMessage(message)
        print("[WATCH] WC didReceiveMessage payload: \(message)")
        
        // Heart rate update received silently
        
        // Update unit preference if present at top level
        if let unitPref = message["isMetric"] as? Bool {
            self.isMetric = unitPref
        }
        
        // Check message command
        if let command = message["command"] as? String {
            print("[WATCH] Processing command: \(command)")
            
            switch command {
            case "splitNotification":
                processSplitNotification(message)
                
            case "sessionStartAlert":
                processSessionStartAlert(message)
                
            case "requestHealthKitPermissions":
                // Check existing permissions status (don't request again)
                print("[WATCH] Received permission check request from phone")
                checkHealthKitPermissionStatus()
                
            case "startSession", "workoutStarted":
                // Start the session if not already active
                if !isSessionActive {
                    print("[WATCH] startSession/workoutStarted received – beginning workout start flow")
                    // Check for unit preference in the message
                    if let unitPref = message["isMetric"] as? Bool {
                        self.isMetric = unitPref
                    } else {
                        // Default to metric if not specified
                        self.isMetric = true
                    }
                    
                    // CRITICAL: Always reinitialize WorkoutManager for fresh HR streaming
                    print("[WATCH] Reinitializing WorkoutManager for fresh HR streaming")
                    self.workoutManager = WorkoutManager()
                    self.workoutManager.delegate = self
                    
                    // CRITICAL: Reconnect handlers after WorkoutManager reinitialization
                    print("[WATCH] Setting up heart rate and step handlers...")
                    self.setupWorkoutHandlers()
                    
                    // Use existing permissions (already requested on launch)
                    
                    // Starting session from phone command - need to start HealthKit workout
                    DispatchQueue.main.async {
                        print("[WATCH] Setting session flags and calling startSession()")
                        self.isSessionActive = true
                        self.isPaused = false
                        self.sessionStartedFromPhone = true // Mark as phone-initiated
                        self.startSession()
                    }
                }
                
            case "startHeartRateMonitoring":
                // Explicit request from phone to ensure HR streaming starts
                print("[WATCH] Received startHeartRateMonitoring command from phone")
                if !isSessionActive {
                    // Start session with existing permissions
                    print("[WATCH] HR monitoring requested while inactive – starting session")
                    DispatchQueue.main.async {
                        self.isSessionActive = true
                        self.isPaused = false
                        self.sessionStartedFromPhone = true
                        self.startSession()
                    }
                } else {
                    // Nudge immediate HR update
                    self.workoutManager.nudgeHeartRateUpdate()
                }

            case "startStepsMonitoring":
                // Explicit request from phone to ensure steps streaming
                print("[WATCH] Received startStepsMonitoring command from phone")
                self.workoutManager.nudgeStepCountUpdate()

            case "stepsDebugRequest":
                // Send a steps snapshot back to the phone for debugging
                let snapshot: [String: Any] = [
                    "command": "stepsDebug",
                    "steps": self.steps,
                    "isSessionActive": self.isSessionActive,
                    "isPaused": self.isPaused,
                    "timestamp": Date().timeIntervalSince1970
                ]
                print("[WATCH] Sending stepsDebug snapshot: \(snapshot)")
                self.sendMessage(snapshot)
                
            case "stopSession", "workoutStopped", "endSession", "sessionEnded", "sessionComplete":
                // Always perform cleanup on stop commands, regardless of current flags
                DispatchQueue.main.async {
                    self.isSessionActive = false
                    self.isPaused = false
                    self.sessionStartedFromPhone = false // Reset flag on session stop
                    // Stop steps watchdog
                    self.stepsWatchdogTimer?.invalidate()
                    self.stepsWatchdogTimer = nil
                    
                    // Clear the timer status to prevent lock screen persistence
                    self.status = "--"
                    
                    // Reset all session data
                    self.heartRate = 0
                    self.calories = 0
                    self.distanceValue = 0.0
                    self.paceValue = 0.0
                    self.steps = 0
                    self.elevationGain = 0.0
                    self.elevationLoss = 0.0
                    
                    // Stop the workout manager and clear handlers
                    self.workoutManager.stopWorkout()
                    self.workoutManager.setHeartRateHandler { _ in }
                    self.workoutManager.setStepCountHandler { _ in }
                    
                    // Force UI refresh to clear any background state
                    WKInterfaceDevice.current().play(.stop)
                    
                    print("[WATCH] Session terminated, exiting app to return to watch home screen")
                    
                    // Terminate the app to remove from lock screen
                    // Delay slightly to ensure cleanup completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Exit the app completely
                        // This will remove it from the lock screen and prevent battery drain
                        exit(0)
                    }
                }
                
            case "pauseSession":
                // Pause command from phone
                DispatchQueue.main.async {
                    self.pauseCurrentSession()
                }
                
            case "resumeSession":
                // Resume command from phone
                DispatchQueue.main.async {
                    self.resumeCurrentSession()
                }
                
            case "pauseConfirmed":
                // iPhone has confirmed our pause request
                // iPhone confirmed pause - ensuring watch UI is in paused state
                DispatchQueue.main.async {
                    if !self.isPaused {
                        self.isPaused = true
                    }
                }
                
            case "resumeConfirmed":
                // iPhone has confirmed our resume request
                // iPhone confirmed resume - ensuring watch UI is in resumed state
                DispatchQueue.main.async {
                    if self.isPaused {
                        self.isPaused = false
                    }
                }
                
            case "updateSessionState":
                // Direct state or unit update from iPhone (used to sync states)
                if let isPausedVal = message["isPaused"] as? Bool {
                    DispatchQueue.main.async { self.isPaused = isPausedVal }
                }
                if let unitPref = message["isMetric"] as? Bool {
                    DispatchQueue.main.async { self.isMetric = unitPref }
                }
                // If isSessionActive is provided, honor it to ensure proper cleanup
                if let activeVal = message["isSessionActive"] as? Bool {
                    DispatchQueue.main.async {
                        self.isSessionActive = activeVal
                        if !activeVal {
                            // Mirror the full cleanup path used by stop commands
                            self.isPaused = false
                            self.status = "--"
                            self.heartRate = 0
                            self.calories = 0
                            self.distanceValue = 0.0
                            self.paceValue = 0.0
                            self.steps = 0
                            self.elevationGain = 0.0
                            self.elevationLoss = 0.0
                            self.workoutManager.stopWorkout()
                            WKInterfaceDevice.current().play(.stop)
                            // Stop steps watchdog
                            self.stepsWatchdogTimer?.invalidate()
                            self.stepsWatchdogTimer = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                exit(0)
                            }
                        }
                    }
                }
                
            case "updateMetrics":
                print("[SessionManager] Processing updateMetrics command")
                print("[SessionManager] updateMetrics message: \(message)")
                
                // Ensure UI/state mutations occur on main
                DispatchQueue.main.async {
                    // Update current metrics from the phone
                    if let distance = message["distance"] as? Double {
                        self.distanceValue = distance
                    }
                    if let metrics = message["metrics"] as? [String: Any] {
                        if let zone = metrics["hrZone"] as? String {
                            self.currentZone = zone
                        }
                    }
                    
                    if let pace = message["pace"] as? Double {
                        self.paceValue = pace
                    }
                    
                    if let isMetricValue = message["isMetric"] as? Bool {
                        self.isMetric = isMetricValue
                        print("[SessionManager] Updated user's metric preference to: \(self.isMetric)")
                        print("[SessionManager] updateMetrics - Set isMetric to: \(self.isMetric)")
                    }
                }
                
            default:
                // Unknown command received
                break
            }
        }
        
        // Direct check for metrics in the root object (for backward compatibility)
        if let metricsData = message["metrics"] as? [String: Any] {
            DispatchQueue.main.async {
                self.updateMetricsFromData(metricsData)
                // Heart rate metrics updated
            }
        }
        // Update last-known settings when pushed from phone
        if let ruckKg = message["ruckWeightKg"] as? Double {
            self.lastRuckWeightKg = ruckKg
        }
        if let userKg = message["userWeightKg"] as? Double {
            self.lastUserWeightKg = userKg
        }
    }
    
    // Required WCSessionDelegate method, even if not actively used for replies FROM watch
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Handle message that expects a reply. For now, acknowledge receipt.
        // You might want to process the message and send a meaningful reply.
        print("[WATCH] Received message with replyHandler: \(message)")
        delegate?.didReceiveMessage(message) // Forward to existing delegate method
        replyHandler(["status": "received_by_watch"])
    }
    
    // Handle application context
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        // Update UI on the main thread (prevents the SwiftUI threading error)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Process application context the same way as messages
            self.delegate?.didReceiveMessage(applicationContext)
            
            // Update unit preference if sent in applicationContext
            if let unitPref = applicationContext["isMetric"] as? Bool {
                self.isMetric = unitPref
            }
            
            // Update metrics when present
            if let metrics = applicationContext["metrics"] as? [String: Any] {
                self.updateMetricsFromData(metrics)
            }
        }
    }
    
    // Handle user info transfers
    #if os(watchOS)
    // NOTE: sessionDidBecomeInactive and sessionDidDeactivate are iOS-only methods
    // They are not available on watchOS, so we don't implement them here
    
    // NOTE: We've removed sessionReachabilityDidChange as it might also be unavailable
    // We'll use session.isReachable property directly when needed instead
    #endif
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Forward to SessionManagerDelegate
            self.delegate?.didReceiveMessage(userInfo)
            
            // Update metrics when present
            if let metrics = userInfo["metrics"] as? [String: Any] {
                self.updateMetricsFromData(metrics)
            }
        }
    }
    
    // Helper method to consistently update metrics from received data
    private func updateMetricsFromData(_ metrics: [String: Any]) {
        // Ensure mutations on main (redundant with @MainActor but safe when called from non-main contexts)
        DispatchQueue.main.async {
            // Do not force sessionActive here; await explicit start/ACK from phone
            
            // Update heart rate when present (silently)
            if let hr = metrics["heartRate"] as? Double {
                self.heartRate = hr
            }
            
            // Update steps when present
            if let stepCount = metrics["steps"] as? Int {
                self.steps = stepCount
            }
            
            // Update calories when present
            if let cal = metrics["calories"] as? Double {
                self.calories = cal
            }
            
            // Update elevation data when present
            if let elGain = metrics["elevationGain"] as? Double {
                self.elevationGain = elGain
            }
            if let elLoss = metrics["elevationLoss"] as? Double {
                self.elevationLoss = elLoss
            }
            
            // Update distance when present
            if let dist = metrics["distance"] as? Double {
                self.distanceValue = dist
            }
            
            // Update pace when present
            if let pace = metrics["pace"] as? Double {
                self.paceValue = pace
            }
            
            // Update metric/imperial preference when present
            if let isMetricValue = metrics["isMetric"] as? Bool {
                print("[DEBUG] Setting isMetric from nested metrics: \(isMetricValue)")
                self.isMetric = isMetricValue
            } else {
                print("[DEBUG] No isMetric found in nested metrics")
            }
            
            // Update timer/duration when present (for realtime tick updates)
            if let duration = metrics["duration"] as? String {
                self.status = duration
            } else if let durationSeconds = metrics["durationSeconds"] as? Double {
                // Convert seconds to MM:SS format
                let minutes = Int(durationSeconds) / 60
                let seconds = Int(durationSeconds) % 60
                self.status = String(format: "%02d:%02d", minutes, seconds)
            }
            
            // Update paused state when present
            if let pausedBool = metrics["isPaused"] as? Bool {
                self.isPaused = pausedBool
            } else if let pausedInt = metrics["isPaused"] as? Int {
                self.isPaused = pausedInt == 1
            }
        }
    }
    
    // Process a split notification message
    func processSplitNotification(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Extract split notification data
            if let splitDistance = message["splitDistance"] as? String,
               let splitTime = message["splitTime"] as? String,
               let totalDistance = message["totalDistance"] as? String,
               let totalTime = message["totalTime"] as? String {
                
                // Update properties
                self.splitDistance = splitDistance
                self.splitTime = splitTime
                self.totalDistance = totalDistance
                self.totalTime = totalTime
                
                // Extract calories and elevation if present
                self.splitCalories = message["splitCalories"] as? String ?? ""
                self.splitElevation = message["splitElevation"] as? String ?? ""
                
                // Show the notification
                self.showingSplitNotification = true
                
                // Check if should vibrate (defaulting to true if not specified)
                let shouldVibrate = message["shouldVibrate"] as? Bool ?? true
                
                // Play haptic feedback for the split notification if requested
                if shouldVibrate {
                    // Play notification haptic feedback
                    WKInterfaceDevice.current().play(.notification)
                    
                    // For stronger feedback, you could use success + notification
                    // Uncomment if you want a stronger double-haptic
                    // DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    //    WKInterfaceDevice.current().play(.success)
                    // }
                }
                
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self.showingSplitNotification = false
                }
            }
        }
    }
    
    // Process a session start alert message
    func processSessionStartAlert(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("[WATCH] Received session start alert")
            
            // Extract alert data
            let title = message["title"] as? String ?? "Session Started"
            let alertMessage = message["message"] as? String ?? "Ruck session active"
            let shouldVibrate = message["shouldVibrate"] as? Bool ?? true
            
            // Play vibration if requested
            if shouldVibrate {
                print("[WATCH] Playing session start vibration")
                WKInterfaceDevice.current().play(.notification)
                
                // Optional: Add a second haptic for emphasis
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    WKInterfaceDevice.current().play(.success)
                }
            }
            
            print("[WATCH] Session start alert processed: \(title) - \(alertMessage)")
        }
    }

    // MARK: - Session Control Methods
    
    /// Pause the current session on the watch
    public func pauseCurrentSession() {
        guard isSessionActive && !isPaused else {
            print("[WATCH] Cannot pause - session not active or already paused")
            return
        }
        
        print("[WATCH] Pausing watch session...")
        
        // Update state
        isPaused = true
        
        // Note: HealthKit workouts pause automatically when watch detects no movement
        // We just track the paused state here for UI purposes
        print("[WATCH] Session paused successfully - workout will auto-pause on no movement")
        
        // Send confirmation to phone
        sendMessage([
            "command": "pauseConfirmed",
            "isPaused": true,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    /// Resume the current session on the watch
    public func resumeCurrentSession() {
        guard isSessionActive && isPaused else {
            print("[WATCH] Cannot resume - session not active or not paused")
            return
        }
        
        print("[WATCH] Resuming watch session...")
        
        // Update state
        isPaused = false
        
        // Note: HealthKit workouts resume automatically when watch detects movement
        // We just track the resumed state here for UI purposes
        print("[WATCH] Session resumed successfully - workout will auto-resume on movement")
        
        // Send confirmation to phone
        sendMessage([
            "command": "resumeConfirmed",
            "isPaused": false,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// Send current session state to phone
    private func sendSessionStateToPhone() {
        // This could send pause/resume state to phone via WatchConnectivity
        // For now just log the intent
        print("[WATCH] Session state sync - isPaused: \(isPaused), isActive: \(isSessionActive)")
    }
    
}

// MARK: - WorkoutManagerDelegate Implementation
extension SessionManager {
    public func workoutDidEnd() {
        DispatchQueue.main.async {
            self.isSessionActive = false
            self.isPaused = false
            self.status = "--"
            self.heartRate = 0
            self.calories = 0
            self.elevationGain = 0.0
            self.elevationLoss = 0.0
            self.steps = 0
            self.distanceValue = 0.0
            self.paceValue = 0.0
            self.splitDistance = ""
            self.splitTime = ""
            self.totalDistance = ""
            self.totalTime = ""
            // Stop steps watchdog
            self.stepsWatchdogTimer?.invalidate()
            self.stepsWatchdogTimer = nil
            
            // Clear any background activities and force app state refresh
            WKInterfaceDevice.current().play(.stop)
            
            // Log workout end for debugging
            print("[WORKOUT] Workout ended via delegate - all state cleared")
            
            // Terminate the app to remove from lock screen
            // Delay slightly to ensure cleanup completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Exit the app completely
                // This will remove it from the lock screen and prevent battery drain
                exit(0)
            }
        }
    }
}

// MARK: - Steps Watchdog (Debugging)
extension SessionManager {
    private func startStepsWatchdog() {
        stepsWatchdogTimer?.invalidate()
        stepsWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            if let last = self.lastStepsUpdateAt {
                let delta = now.timeIntervalSince(last)
                if delta > 90.0 { // 1.5 minutes without steps
                    print("[WATCH] [STEPS_DEBUG] No steps for \(Int(delta))s – nudging update and sending snapshot")
                    self.workoutManager.nudgeStepCountUpdate()
                    let snapshot: [String: Any] = [
                        "command": "stepsDebug",
                        "steps": self.steps,
                        "isSessionActive": self.isSessionActive,
                        "isPaused": self.isPaused,
                        "timestamp": Date().timeIntervalSince1970,
                        "note": "watchdog_nudge"
                    ]
                    self.sendMessage(snapshot)
                }
            } else {
                print("[WATCH] [STEPS_DEBUG] No steps received yet – sending initial snapshot and nudge")
                self.workoutManager.nudgeStepCountUpdate()
                let snapshot: [String: Any] = [
                    "command": "stepsDebug",
                    "steps": self.steps,
                    "isSessionActive": self.isSessionActive,
                    "isPaused": self.isPaused,
                    "timestamp": Date().timeIntervalSince1970,
                    "note": "initial_nudge"
                ]
                self.sendMessage(snapshot)
            }
        }
    }
}
#endif

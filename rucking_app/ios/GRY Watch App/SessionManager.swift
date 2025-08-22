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

public class SessionManager: NSObject, ObservableObject, WCSessionDelegate, WorkoutManagerDelegate {
    // WorkoutManager for HealthKit access
    private var workoutManager: WorkoutManager!
    // Published properties for SwiftUI
    @Published var status: String = "--"
    @Published var heartRate: Int = 0
    @Published var calories: Int = 0
    @Published var elevationGain: Double = 0.0
    @Published var elevationLoss: Double = 0.0
    @Published var distanceValue: Double = 0.0
    @Published var paceValue: Double = 0.0
    @Published var isPaused: Bool = false
    @Published var isSessionActive: Bool = false
    
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
        heartRate > 0 ? "\(heartRate)" : "--"
    }
    var caloriesText: String {
        calories > 0 ? "\(calories)" : "--"
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
        
        // Convert seconds to minutes:seconds format
        let minutes = Int(paceValue) / 60
        let seconds = Int(paceValue) % 60
        
        // Format as MM:SS (no unit since label will indicate it's pace)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func startSession() {
        // Leave status as "--" for cleaner UI
        
        // Set up heart rate handler to send heart rate updates to the phone
        workoutManager.setHeartRateHandler { [weak self] (heartRate: Double) in
            guard let self = self else { return }
            // Update UI with heart rate
            DispatchQueue.main.async {
                self.heartRate = Int(heartRate)
            }
            // Send heart rate to iOS app silently
            self.sendHeartRate(heartRate)
        }
        
        // Request HealthKit permissions
        workoutManager.requestAuthorization { success, error in
            if success {
                // HealthKit authorization successful
                // Start workout session to get heart rate
                DispatchQueue.main.async {
                    self.workoutManager.startWorkout { error in
                        if let error = error {
                            print("[WATCH] Failed to start workout: \(error.localizedDescription)")
                        } else {
                            // Workout session started successfully
                            // Send start payload with timestamp for backfill
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
                    }
                }
            } else if let error = error {
                print("[ERROR] HealthKit authorization failed: \(error.localizedDescription)")
            }
        }
    }

    static let shared = SessionManager()
    weak var delegate: SessionManagerDelegate?
    private let session: WCSession
    
    override init() {
        session = WCSession.default
        // Initialize WorkoutManager after super.init()
        super.init()
        workoutManager = WorkoutManager()
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        // Ensure we receive callbacks when the workout ends
        workoutManager.delegate = self
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
            session.sendMessage(message, replyHandler: { reply in
                // Heart rate receipt confirmed - no logging needed
            }) { error in
                // Only log errors
                print("[WATCH] Error sending heart rate: \(error.localizedDescription)")
            }
        } else {
            // Queue as user info for background delivery
            session.transferUserInfo(["type": "hr_sample", "bpm": heartRate, "timestamp": Date().timeIntervalSince1970])
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
        
        // Heart rate update received silently
        
        // Update unit preference if present at top level
        if let unitPref = message["isMetric"] as? Bool {
            self.isMetric = unitPref
        }
        
        // Check message command
        if let command = message["command"] as? String {
            // Processing command from message
            
            switch command {
            case "splitNotification":
                processSplitNotification(message)
                
            case "sessionStartAlert":
                processSessionStartAlert(message)
                
            case "startSession", "workoutStarted":
                print("[SessionManager] Received workoutStarted command")
                print("[SessionManager] Full message received: \(message)")
                print("[SessionManager] isMetric from message: \(message["isMetric"] ?? "NOT_FOUND")")
                
                // Start the session if not already active
                if !isSessionActive {
                    // Check for unit preference in the message
                    if let unitPref = message["isMetric"] as? Bool {
                        self.isMetric = unitPref
                        print("Setting unit preference to \(unitPref ? "metric" : "standard")")
                        print("[SessionManager] Set isMetric to: \(self.isMetric)")
                    } else {
                        // Default to metric if not specified
                        self.isMetric = true
                        print("[SessionManager] Defaulted isMetric to: \(self.isMetric) (value not found or wrong type)")
                    }
                    
                    // Starting session from phone command
                    DispatchQueue.main.async {
                        self.isSessionActive = true
                        self.isPaused = false
                        self.startSession()
                    }
                }
                
            case "stopSession", "workoutStopped", "endSession", "sessionEnded", "sessionComplete":
                // Stop the session if active
                if isSessionActive {
                    // Stopping session from phone command
                    DispatchQueue.main.async {
                        self.isSessionActive = false
                        self.isPaused = false
                        
                        // Clear the timer status to prevent lock screen persistence
                        self.status = "--"
                        
                        // Reset all session data
                        self.heartRate = 0
                        self.calories = 0
                        self.distanceValue = 0.0
                        self.paceValue = 0.0
                        self.elevationGain = 0.0
                        self.elevationLoss = 0.0
                        
                        // Stop the workout manager
                        self.workoutManager.stopWorkout()
                        
                        // Force UI refresh to clear any background state
                        WKInterfaceDevice.current().play(.stop)
                        
                        // Terminate the app to remove from lock screen
                        // Delay slightly to ensure cleanup completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Exit the app completely
                            // This will remove it from the lock screen and prevent battery drain
                            exit(0)
                        }
                    }
                }
                
            case "pauseSession":
                // Pause command from phone
                DispatchQueue.main.async {
                    self.isPaused = true
                }
                
            case "resumeSession":
                // Resume command from phone
                DispatchQueue.main.async {
                    self.isPaused = false
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
                
            case "updateMetrics":
                print("[SessionManager] Processing updateMetrics command")
                print("[SessionManager] updateMetrics message: \(message)")
                
                // Update current metrics from the phone
                if let distance = message["distance"] as? Double {
                    self.distanceValue = distance
                }
                
                if let pace = message["pace"] as? Double {
                    self.paceValue = pace
                }
                
                if let isMetricValue = message["isMetric"] as? Bool {
                    self.isMetric = isMetricValue
                    print("[SessionManager] Updated user's metric preference to: \(self.isMetric)")
                    print("[SessionManager] updateMetrics - Set isMetric to: \(self.isMetric)")
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
        // Mark session as active when receiving metrics
        self.isSessionActive = true
        
        // Update heart rate when present (silently)
        if let hr = metrics["heartRate"] as? Double {
            self.heartRate = Int(hr)
        }
        
        // Update calories when present
        if let cal = metrics["calories"] as? Double {
            self.calories = Int(cal)
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
        
        // Update active state when present (to handle phone-side session end)
        if let activeBool = metrics["isSessionActive"] as? Bool {
            self.isSessionActive = activeBool
            if !activeBool {
                // Session ended - comprehensive cleanup
                self.isPaused = false
                self.status = "--"
                
                // Reset all session metrics
                self.heartRate = 0
                self.calories = 0
                self.distanceValue = 0.0
                self.paceValue = 0.0
                self.elevationGain = 0.0
                self.elevationLoss = 0.0
                
                // Ensure workout is stopped and UI reset
                self.workoutManager.stopWorkout()
                
                // Clear any background state
                WKInterfaceDevice.current().play(.stop)
            }
        } else if let activeInt = metrics["isSessionActive"] as? Int {
            let active = activeInt == 1
            self.isSessionActive = active
            if !active {
                // Session ended - comprehensive cleanup
                self.isPaused = false
                self.status = "--"
                
                // Reset all session metrics
                self.heartRate = 0
                self.calories = 0
                self.distanceValue = 0.0
                self.paceValue = 0.0
                self.elevationGain = 0.0
                self.elevationLoss = 0.0
                
                self.workoutManager.stopWorkout()
                
                // Clear any background state
                WKInterfaceDevice.current().play(.stop)
            }
        }
        
        // Update timer display from duration
        if let duration = metrics["duration"] as? Int {
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            let seconds = duration % 60
            
            // Always use HH:MM:SS format for consistency regardless of duration
            // This prevents the UI from "wrapping" when going over an hour
            self.status = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
            self.distanceValue = 0.0
            self.paceValue = 0.0
            self.splitDistance = ""
            self.splitTime = ""
            self.totalDistance = ""
            self.totalTime = ""
            
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
#endif

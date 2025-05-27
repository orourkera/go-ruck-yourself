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
        if !self._isMetric {
            let gainFeet = Int(elevationGain * 3.28084)
            let lossFeet = Int(elevationLoss * 3.28084)
            return "+\(gainFeet)/-\(lossFeet) ft"
        } else {
            return "+\(Int(elevationGain))/-\(Int(elevationLoss)) m"
        }
    }
    var distance: String {
        if distanceValue <= 0 {
            return "--"
        }
        
        // Show miles if using imperial units, otherwise kilometers
        if !self._isMetric {
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
        
        // Get user's preferred unit (metric or imperial)
        // If we can't determine the preference, default to metric (km)
        let unit = self._isMetric ? "km" : "mi"
        
        // Format as MM:SS/unit
        return String(format: "%d:%02d/%@", minutes, seconds, unit)
    }
    
    // Store user's metric preference
    private var _isMetric: Bool = true // Default to metric
    
    // Public accessor for metric preference with getter and setter
    var isMetric: Bool {
        get {
            return _isMetric
        }
        set {
            _isMetric = newValue
        }
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
            // Session not activated, message not sent.
            return
        }
        
        // Ensure message has proper type format for Dart side casting
        // This ensures the message is always a Dictionary with String keys and valid JSON values
        if var sanitizedMessage = message as? [String: Any] {
            // Log the message being sent for debugging
            // SessionManager sending message

            session.sendMessage(sanitizedMessage, replyHandler: nil) { error in
                print("Error sending message: \(error.localizedDescription)")
            }
        } else {
            // Error: Could not sanitize message to proper format
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
            // Fallback to regular send which might be less reliable
            sendMessage(message)
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
        
        // Don't check isPaused here since togglePauseResume has already set it
        // This prevents the function from returning early when it should continue
        
        print("[DEBUG] Pausing session from watch")
        // Make sure isPaused is true (should already be set by togglePauseResume)
        DispatchQueue.main.async {
            if !self.isPaused {
                self.isPaused = true
            }
        }
        
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
    func togglePauseResume() {
        // Toggle pause/resume called
        print("[DEBUG] togglePauseResume called, current isPaused state: \(isPaused)")
        
        // Set local state immediately for responsive UI
        let newPausedState = !isPaused
        DispatchQueue.main.async {
            self.isPaused = newPausedState
        }
        
        // Then perform the actual action
        if newPausedState {
            pauseSession()
        } else {
            resumeSession()
        }
        
        print("[DEBUG] togglePauseResume executed, new isPaused state: \(isPaused)")
    }
    
    // Resume the session from the watch
    func resumeSession() {
        // Emit a debug tap signal to the phone so we can confirm the watch button was pressed.
        sendMessage(["command": "debug_watchResumeTapped"])  // DEBUG ONLY
        
        guard isSessionActive else { 
            print("[DEBUG] Cannot resume: session not active")
            return 
        }
        
        // Don't check isPaused here since togglePauseResume has already updated it
        // This prevents the function from returning early when it should continue
        
        print("[DEBUG] Resuming session from watch")
        // Make sure isPaused is false (should already be set by togglePauseResume)
        DispatchQueue.main.async {
            if self.isPaused {
                self.isPaused = false
            }
        }
        
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
        
        // Check message command
        if let command = message["command"] as? String {
            // Processing command from message
            
            switch command {
            case "splitNotification":
                processSplitNotification(message)
                
            case "startSession", "workoutStarted":
                // Start the session if not already active
                if !isSessionActive {
                    // Starting session from phone command
                    DispatchQueue.main.async {
                        self.isSessionActive = true
                        self.isPaused = false
                        self.startSession()
                    }
                }
                
            case "stopSession", "workoutStopped":
                // Stop the session if active
                if isSessionActive {
                    // Stopping session from phone command
                    DispatchQueue.main.async {
                        self.isSessionActive = false
                        self.workoutManager.stopWorkout()
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
                // Direct state update from iPhone (used to sync states)
                if let isPaused = message["isPaused"] as? Bool {
                    // Updating session state
                    DispatchQueue.main.async {
                        self.isPaused = isPaused
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
            self.isMetric = isMetricValue
        }
        
        // Update paused state when present
        if let paused = metrics["isPaused"] as? Int {
            self.isPaused = paused == 1
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
                
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.showingSplitNotification = false
                }
            }
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
        }
    }
}
#endif

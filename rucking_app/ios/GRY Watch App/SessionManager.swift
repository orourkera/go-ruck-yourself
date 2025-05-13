import Foundation
import WatchConnectivity

protocol SessionManagerDelegate: AnyObject {
    func sessionDidActivate()
    func sessionDidDeactivate()
    func didReceiveMessage(_ message: [String: Any])
}

class SessionManager: NSObject, ObservableObject, WCSessionDelegate {
    // WorkoutManager for HealthKit access
    private let workoutManager = WorkoutManager()
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
        elevationGain > 0 ? "+\(Int(elevationGain))/-\(Int(elevationLoss))" : "--"
    }
    var distance: String {
        distanceValue > 0 ? String(format: "%.2f", distanceValue) : "--"
    }
    var pace: String {
        paceValue > 0 ? String(format: "%.1f", paceValue) : "--"
    }

    func startSession() {
        // Leave status as "--" for cleaner UI
        
        // Set up heart rate handler to send heart rate updates to the phone
        workoutManager.setHeartRateHandler { [weak self] heartRate in
            guard let self = self else { return }
            // Update UI with heart rate
            DispatchQueue.main.async {
                self.heartRate = Int(heartRate)
            }
            // Send heart rate to iOS app
            self.sendHeartRate(heartRate)
        }
        
        // Request HealthKit permissions
        workoutManager.requestAuthorization { success, error in
            if success {
                print("[WATCH] HealthKit authorization successful")
                // Start workout session to get heart rate
                DispatchQueue.main.async {
                    self.workoutManager.startWorkout { error in
                        if let error = error {
                            print("[WATCH] Failed to start workout: \(error.localizedDescription)")
                        } else {
                            print("[WATCH] Workout session started successfully")
                        }
                    }
                }
            } else if let error = error {
                print("[WATCH] HealthKit authorization failed: \(error.localizedDescription)")
            }
        }
    }

    static let shared = SessionManager()
    weak var delegate: SessionManagerDelegate?
    private let session: WCSession
    
    override init() {
        session = WCSession.default
        super.init()
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }
    
    func sendMessage(_ message: [String: Any]) {
        guard session.activationState == .activated else {
            print("Session not activated, message not sent.")
            return
        }
        
        // Log the message being sent for debugging
        print(" [WATCH] SessionManager attempting to send message: \(message)")

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending message: \(error.localizedDescription)")
        }
    }
    
    func sendHeartRate(_ heartRate: Double) {
        let message: [String: Any] = ["heartRate": heartRate, "command": "watchHeartRateUpdate"]
        sendMessage(message)
        print(" [WATCH] SessionManager: Sent heart rate to iOS: \(heartRate) bpm")
    }
    
    // Pause the session from the watch
    func pauseSession() {
        guard isSessionActive && !isPaused else { return }
        
        print("[WATCH] Pausing session from watch")
        isPaused = true
        
        // Send pause command to the iPhone app
        let message: [String: Any] = ["command": "pauseSession", "action": "pauseSession"]
        sendMessage(message)
    }
    
    // Resume the session from the watch
    func resumeSession() {
        guard isSessionActive && isPaused else { return }
        
        print("[WATCH] Resuming session from watch")
        isPaused = false
        
        // Send resume command to the iPhone app
        let message: [String: Any] = ["command": "resumeSession", "action": "resumeSession"]
        sendMessage(message)
    }
    
    // Toggle between pause and resume
    func togglePauseResume() {
        if isPaused {
            resumeSession()
        } else {
            pauseSession()
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            delegate?.sessionDidActivate()
        } else {
            delegate?.sessionDidDeactivate()
        }
        if let error = error {
            print("Session activation failed: \(error.localizedDescription)")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        delegate?.didReceiveMessage(message)
        
        print("[WATCH] Received message: \(message)")
        
        // Check message command
        if let command = message["command"] as? String {
            switch command {
            case "splitNotification":
                processSplitNotification(message)
                
            case "startSession":
                self.isSessionActive = true
                self.isPaused = false
                print("[WATCH] Session started from phone")
                
            case "pauseSession":
                self.isPaused = true
                print("[WATCH] Session paused from phone")
                
            case "resumeSession":
                self.isPaused = false
                print("[WATCH] Session resumed from phone")
                
            case "endSession":
                self.isSessionActive = false
                self.isPaused = false
                print("[WATCH] Session ended from phone")
                
            default: break
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        delegate?.didReceiveMessage(message)
        
        // Check message command
        if let command = message["command"] as? String {
            switch command {
            case "splitNotification":
                processSplitNotification(message)
                
            case "startSession":
                self.isSessionActive = true
                self.isPaused = false
                print("[WATCH] Session started from phone (with reply)")
                
            case "pauseSession":
                self.isPaused = true
                print("[WATCH] Session paused from phone (with reply)")
                
            case "resumeSession":
                self.isPaused = false
                print("[WATCH] Session resumed from phone (with reply)")
                
            case "endSession":
                self.isSessionActive = false
                self.isPaused = false
                print("[WATCH] Session ended from phone (with reply)")
                
            default: break
            }
        }
        
        // Send the reply that message was received
        replyHandler(["received": true])
    }
    
    // Handle application context
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
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
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
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
        
        // Update heart rate when present
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
        
        // Update paused state when present
        if let paused = metrics["isPaused"] as? Int {
            self.isPaused = paused == 1
        }
        
        // Update timer display from duration
        if let duration = metrics["duration"] as? Int {
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            let seconds = duration % 60
            
            // Format as HH:MM:SS if hours > 0, otherwise MM:SS
            if hours > 0 {
                self.status = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            } else {
                self.status = String(format: "%02d:%02d", minutes, seconds)
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
                
                // Show the notification
                self.showingSplitNotification = true
                
                print("[WATCH] Received split notification: \(splitDistance) in \(splitTime)")
                
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.showingSplitNotification = false
                }
            }
        }
    }
}

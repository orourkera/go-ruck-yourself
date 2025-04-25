import Foundation
import WatchConnectivity
import HealthKit

class SessionManager: NSObject, ObservableObject {
    static let shared = SessionManager()
    
    // Session properties
    @Published var isSessionActive = false
    @Published var isPaused = false
    @Published var sessionDuration: TimeInterval = 0
    @Published var distance: Double = 0 // in meters
    @Published var pace: Double = 0 // min/km
    @Published var heartRate: Double? = nil
    @Published var caloriesBurned: Double = 0
    @Published var ruckWeight: Double = 0 // in kg
    
    // Watch connectivity
    private var wcSession: WCSession?
    private let healthKitManager = HealthKitManager.shared
    
    // Timer for updating session duration when watch is the source of truth
    private var durationTimer: Timer?
    private var sessionStartTime: Date?
    private var accumulatedTime: TimeInterval = 0
    
    private override init() {
        super.init()
        setupWatchConnectivity()
        healthKitManager.requestAuthorization()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }
    
    // MARK: - Session Control
    
    func startSession(weight: Double) {
        ruckWeight = weight
        isSessionActive = true
        isPaused = false
        sessionStartTime = Date()
        
        // Start the timer for updating duration
        startDurationTimer()
        
        // Start heart rate monitoring
        healthKitManager.startHeartRateMonitoring { [weak self] heartRate in
            DispatchQueue.main.async {
                self?.heartRate = heartRate
                self?.sendHeartRateToPhone(heartRate)
            }
        }
        
        // Send start command to phone
        sendMessageToPhone([
            "command": "startSession",
            "ruckWeight": weight
        ])
    }
    
    func pauseSession() {
        isPaused = true
        
        // Pause the timer
        durationTimer?.invalidate()
        
        // Calculate accumulated time
        if let startTime = sessionStartTime {
            accumulatedTime += Date().timeIntervalSince(startTime)
            sessionStartTime = nil
        }
        
        // Send pause command to phone
        sendMessageToPhone([
            "command": "pauseSession"
        ])
    }
    
    func resumeSession() {
        isPaused = false
        sessionStartTime = Date()
        
        // Restart the timer
        startDurationTimer()
        
        // Send resume command to phone
        sendMessageToPhone([
            "command": "resumeSession"
        ])
    }
    
    func endSession() {
        // Calculate final stats
        if let startTime = sessionStartTime {
            accumulatedTime += Date().timeIntervalSince(startTime)
        }
        
        // Send end command to phone with final stats
        sendMessageToPhone([
            "command": "endSession",
            "duration": accumulatedTime,
            "distance": distance,
            "calories": caloriesBurned
        ])
        
        // Save workout to HealthKit
        let endTime = Date()
        let startTime = endTime.addingTimeInterval(-accumulatedTime)
        
        healthKitManager.saveWorkout(
            startDate: startTime,
            endDate: endTime,
            distance: distance,
            calories: caloriesBurned,
            ruckWeight: ruckWeight
        )
        
        // Reset session state
        resetSession()
    }
    
    private func resetSession() {
        isSessionActive = false
        isPaused = false
        sessionDuration = 0
        distance = 0
        pace = 0
        heartRate = nil
        caloriesBurned = 0
        sessionStartTime = nil
        accumulatedTime = 0
        durationTimer?.invalidate()
        healthKitManager.stopHeartRateMonitoring()
    }
    
    // MARK: - Timer Management
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            
            if let startTime = self.sessionStartTime {
                let currentDuration = self.accumulatedTime + Date().timeIntervalSince(startTime)
                self.sessionDuration = currentDuration
                
                // Update calories burned estimate
                self.updateCaloriesBurned()
            }
        }
    }
    
    private func updateCaloriesBurned() {
        // Simple calorie calculation based on MET value for rucking (approximately 6-8 METs)
        // MET * weight (kg) * duration (hours)
        let metValue: Double = 7.0 // Moderate to vigorous rucking
        let weightWithRuck = 70.0 + ruckWeight // Assuming 70kg person + ruck weight
        let hours = sessionDuration / 3600.0
        
        caloriesBurned = metValue * weightWithRuck * hours
    }
    
    // MARK: - Communication Methods
    
    func sendHeartRateToPhone(_ heartRate: Double?) {
        guard let heartRate = heartRate else { return }
        
        sendMessageToPhone([
            "command": "updateHeartRate",
            "heartRate": heartRate
        ])
    }
    
    private func sendMessageToPhone(_ message: [String: Any]) {
        guard let wcSession = wcSession, wcSession.activationState == .activated else {
            print("WCSession not activated, cannot send message")
            return
        }
        
        if wcSession.isReachable {
            wcSession.sendMessage(message, replyHandler: nil) { error in
                print("Error sending message to phone: \(error.localizedDescription)")
            }
        } else {
            // Queue the message for later delivery if not reachable
            wcSession.transferUserInfo(message)
        }
    }
    
    func processReceivedMessage(_ message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        
        DispatchQueue.main.async {
            switch command {
            case "updateSession":
                if let distance = message["distance"] as? Double {
                    self.distance = distance
                }
                if let duration = message["duration"] as? TimeInterval {
                    self.sessionDuration = duration
                }
                if let pace = message["pace"] as? Double {
                    self.pace = pace
                }
                if let isPaused = message["isPaused"] as? Bool {
                    self.isPaused = isPaused
                }
                if let heartRate = message["heartRate"] as? Double {
                    self.heartRate = heartRate
                }
                
            case "startSession":
                if let weight = message["ruckWeight"] as? Double {
                    self.startSession(weight: weight)
                }
                
            case "pauseSession":
                self.pauseSession()
                
            case "resumeSession":
                self.resumeSession()
                
            case "endSession":
                self.endSession()
                
            default:
                break
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension SessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        
        print("WCSession activated with state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        processReceivedMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        processReceivedMessage(userInfo)
    }
}

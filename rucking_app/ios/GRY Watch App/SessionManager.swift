//
//  SessionManager.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import Foundation
import WatchConnectivity
import HealthKit

@available(iOS 13.0, watchOS 9.0, *)
class SessionManager: NSObject, ObservableObject, WCSessionDelegate, HealthKitDelegate {
    static let shared = SessionManager()
    
    // Session properties
    @Published var isSessionActive = false
    @Published var isPaused = false
    @Published var startDate = Date()  // Use a non-optional Date with a default value
    @Published var isTimerRunning = false  // Track if timer is running instead of using optional
    @Published var elapsedDuration: TimeInterval = 0
    @Published var distance: Double = 0 // in meters
    @Published var calories: Double = 0 // in calories
    @Published var pace: Double = 0 // in minutes per km
    @Published var heartRate: Double = 0 // in BPM
    @Published var ruckWeight: Double = 0 // in kg
    @Published var elevationGain: Double = 0 // in meters
    
    // For session review
    @Published var isShowingSessionReview = false
    @Published var sessionSummary: SessionSummary?
    
    // User preferences
    @Published var userId: String = ""
    @Published var useMetricUnits: Bool = true // Default to metric
    
    // Watch connectivity
    private var wcSession: WCSession?
    private let healthKitManager = HealthKitManager.shared
    private var timer: Timer?
    
    override init() {
        super.init()
        setupWatchConnectivity()
        
        // Set this class as the HealthKit delegate
        healthKitManager.delegate = self
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }
    
    // MARK: - Session Control
    
    func startSession(withWeight weight: Double) {
        ruckWeight = weight
        isSessionActive = true
        isPaused = false
        startDate = Date()
        isTimerRunning = true
        
        // Start the timer for updating duration
        startTimer()
        
        // Start heart rate monitoring
        healthKitManager.startHeartRateMonitoring()
        
        // Send start command to phone
        sendMessageToPhone([
            "command": "startSession",
            "ruckWeight": weight
        ])
    }
    
    func pauseSession() {
        isPaused = true
        isTimerRunning = false
        
        // Pause the timer
        timer?.invalidate()
        
        // Calculate accumulated time
        elapsedDuration += Date().timeIntervalSince(startDate)
        
        // Send pause command to phone
        sendMessageToPhone([
            "command": "pauseSession"
        ])
    }
    
    func resumeSession() {
        isPaused = false
        startDate = Date()
        isTimerRunning = true
        
        // Restart the timer
        startTimer()
        
        // Send resume command to phone
        sendMessageToPhone([
            "command": "resumeSession"
        ])
    }
    
    func endSession() {
        // Calculate final stats
        elapsedDuration += Date().timeIntervalSince(startDate)
        
        // Create session summary for review
        let summary = SessionSummary(
            duration: elapsedDuration,
            distance: distance,
            calories: calories,
            avgHeartRate: heartRate, // Using current HR as average (in a real app you'd calculate the average)
            ruckWeight: ruckWeight,
            elevationGain: elevationGain
        )
        
        // Save workout to HealthKit
        let endTime = Date()
        let workoutStartTime = endTime.addingTimeInterval(-elapsedDuration)
        
        healthKitManager.saveWorkout(
            startDate: workoutStartTime,
            endDate: endTime,
            distance: distance,
            calories: calories,
            ruckWeight: ruckWeight
        )
        
        // Send end command to phone with final stats
        sendMessageToPhone([
            "command": "endSession",
            "duration": elapsedDuration,
            "distance": distance,
            "calories": calories
        ])
        
        // Show session review
        self.sessionSummary = summary
        self.isShowingSessionReview = true
        
        // Reset session state after review is shown
        resetSession()
    }
    
    private func resetSession() {
        isSessionActive = false
        isPaused = false
        isTimerRunning = false
        elapsedDuration = 0
        distance = 0
        pace = 0
        heartRate = 0
        calories = 0
        elevationGain = 0
        startDate = Date()
        timer?.invalidate()
        healthKitManager.stopHeartRateMonitoring()
    }
    
    // Method to dismiss session review and clean up
    func dismissSessionReview() {
        isShowingSessionReview = false
        sessionSummary = nil
    }
    
    // MARK: - Timer Management
    
    private func startTimer() {
        // Using modern Timer API without KeyPath
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isTimerRunning else { return }
            
            if !self.isPaused {
                self.elapsedDuration += 1.0
                
                // Update pace calculation if distance > 0
                if self.distance > 0 {
                    // Convert from minutes per km
                    self.pace = (self.elapsedDuration / 60) / (self.distance / 1000)
                }
                
                // Estimate calories burned every second
                // Very rough estimation based on weight, speed, and time
                let MET = 7.0 // MET for rucking (estimate)
                let caloriesPerSecond = (MET * 3.5 * (70 + self.ruckWeight)) / 60 / 60
                self.calories += caloriesPerSecond
            }
        }
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
            wcSession.sendMessage(message, replyHandler: nil, errorHandler: { error in
                print("Error sending message to phone: \(error.localizedDescription)")
            })
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
                    self.elapsedDuration = duration
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
                if let elevation = message["elevation"] as? Double {
                    self.elevationGain = elevation
                }
                
            case "startSession":
                if let weight = message["ruckWeight"] as? Double {
                    self.startSession(withWeight: weight)
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
    
    // MARK: - HealthKitDelegate
    
    func heartRateUpdated(heartRate: Double) {
        // Update the local heart rate property
        self.heartRate = heartRate
        
        // Send heart rate to the phone if session is active
        if isSessionActive {
            sendMessageToPhone([
                "command": "updateHeartRate",
                "heartRate": heartRate
            ])
        }
    }
    
    // MARK: - WCSessionDelegate Methods
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle session activation completion
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        
        print("WCSession activated with state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        processReceivedMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Process user info on the main thread
        DispatchQueue.main.async {
            self.handleReceivedUserInfo(userInfo)
        }
    }
    
    private func handleReceivedUserInfo(_ userInfo: [String: Any]) {
        // Check the type of information received
        guard let type = userInfo["type"] as? String else {
            print("Received user info without type field")
            return
        }
        
        switch type {
        case "userPreferences":
            if let userId = userInfo["userId"] as? String {
                self.userId = userId
            }
            if let useMetricUnits = userInfo["useMetricUnits"] as? Bool {
                self.useMetricUnits = useMetricUnits
            }
            print("Updated user preferences: userId=\(self.userId), useMetricUnits=\(self.useMetricUnits)")
            
        default:
            print("Received unknown user info type: \(type)")
        }
    }
    
    #if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        // Handle reachability changes if needed
    }
    #endif
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate session if needed
        print("WCSession deactivated")
        WCSession.default.activate()
    }
    #endif
}

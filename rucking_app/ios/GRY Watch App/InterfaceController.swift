import WatchKit
import Foundation
import WatchConnectivity
import HealthKit

class InterfaceController: WKInterfaceController, WCSessionDelegate {
    
    @IBOutlet weak var heartRateLabel: WKInterfaceLabel!
    @IBOutlet weak var distanceLabel: WKInterfaceLabel!
    @IBOutlet weak var caloriesLabel: WKInterfaceLabel!
    @IBOutlet weak var paceLabel: WKInterfaceLabel!
    @IBOutlet weak var elevationLabel: WKInterfaceLabel!
    @IBOutlet weak var statusLabel: WKInterfaceLabel!
    
    private var session: WCSession?
    private var workoutManager: WorkoutManager?
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Initialize WatchConnectivity session
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            if session?.activationState != .activated {
                print("Activating Watch session...")
                session?.activate()
            } else {
                print("Watch session already activated with state: \(session?.activationState.rawValue ?? -1)")
            }
            print("Session pairing status checks are not available in watchOS")
        } else {
            print("WatchConnectivity is not supported on this device.")
        }
        
        // Set initial UI state - attempt to set even if outlets are not connected
        if statusLabel == nil {
            print("statusLabel outlet is not connected in storyboard!")
        } else {
            statusLabel.setText("GRY Watch App: Initializing...")
        }
        if heartRateLabel == nil {
            print("heartRateLabel outlet is not connected in storyboard!")
        } else {
            heartRateLabel.setText("Heart Rate: -- bpm")
        }
        if distanceLabel == nil {
            print("distanceLabel outlet is not connected in storyboard!")
        } else {
            distanceLabel.setText("Distance: -- km")
        }
        if caloriesLabel == nil {
            print("caloriesLabel outlet is not connected in storyboard!")
        } else {
            caloriesLabel.setText("Calories: --")
        }
        if paceLabel == nil {
            print("paceLabel outlet is not connected in storyboard!")
        } else {
            paceLabel.setText("Pace: -- min/km")
        }
        if elevationLabel == nil {
            print("elevationLabel outlet is not connected in storyboard!")
        } else {
            elevationLabel.setText("Elevation: -- m")
        }
        updateStatusLabel()
        
        // Initialize WorkoutManager for HealthKit
        workoutManager = WorkoutManager()
        setupHealthKit()
    }
    
    override func willActivate() {
        super.willActivate()
        // Check session state when view becomes visible
        if let session = session {
            switch session.activationState {
            case .activated:
                statusLabel.setText("Connected")
                print("Updated UI: Session is activated.")
            case .inactive, .notActivated:
                statusLabel.setText("Not Connected")
                print("Updated UI: Session is not activated. Current state: \(session.activationState.rawValue)")
            @unknown default:
                statusLabel.setText("Unknown State")
                print("Updated UI: Session state is unknown.")
            }
        }
    }
    
    override func didDeactivate() {
        super.didDeactivate()
    }
    
    // Setup HealthKit authorization and heart rate handling
    private func setupHealthKit() {
        guard let manager = workoutManager else { return }
        
        if manager.isHealthKitAvailable {
            manager.requestAuthorization { [weak self] (success, error) in
                guard let self = self else { return }
                if success {
                    // Set handler for heart rate updates
                    manager.setHeartRateHandler { heartRate in
                        self.heartRateLabel.setText(String(format: "HR: %.0f bpm", heartRate))
                        self.sendHeartRate(heartRate)
                    }
                } else if let error = error {
                    self.statusLabel.setText("HealthKit Error: \(error.localizedDescription)")
                }
            }
        } else {
            statusLabel.setText("HealthKit Not Available")
        }
    }
    
    // MARK: - WCSessionDelegate Methods
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusLabel()
        }
        if let error = error {
            print("Session activation error: \(error.localizedDescription)")
        } else {
            print("Session activation completed with state: \(activationState.rawValue)")
        }
    }
    
    private func updateStatusLabel() {
        guard let session = session else {
            if statusLabel != nil {
                statusLabel.setText("Status: Not Supported")
            }
            return
        }
        
        switch session.activationState {
        case .activated:
            if statusLabel != nil {
                statusLabel.setText("Status: Connected")
            }
            print("Updated UI: Session is activated.")
        case .inactive, .notActivated:
            if statusLabel != nil {
                statusLabel.setText("Status: Disconnected")
            }
            print("Updated UI: Session is not activated. Current state: \(session.activationState.rawValue)")
        @unknown default:
            if statusLabel != nil {
                statusLabel.setText("Status: Unknown")
            }
            print("Updated UI: Session state is unknown.")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("🔔 [WATCH] Received message from iOS: \(message)")
        // Make sure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update the status label regardless of command to show activity
            self.statusLabel.setText("Message received: \(Date().timeIntervalSince1970)")
            
            // Handle incoming messages from iOS app
            if let command = message["command"] as? String {
                print("🔔 [WATCH] Received command: \(command)")
                
                // Make all text labels show we received communication
                self.heartRateLabel.setText("HR Update: \(command)")
                
                switch command {
                case "workoutStarted":
                    self.statusLabel.setText("Workout Active")
                    self.workoutManager?.startWorkout { error in
                        if let error = error {
                            self.statusLabel.setText("Workout Error: \(error.localizedDescription)")
                        }
                    }
                case "workoutStopped":
                    self.statusLabel.setText("Workout Ended")
                    self.workoutManager?.endWorkout { error in
                        if let error = error {
                            self.statusLabel.setText("Workout End Error: \(error.localizedDescription)")
                        }
                    }
                case "updateMetrics":
                    if let metrics = message["metrics"] as? [String: Any] {
                        self.updateMetrics(metrics)
                    }
                case "ping":
                    // Special ping command to test communication
                    self.statusLabel.setText("Ping received!")
                    // Reply back to confirm receipt
                    self.session?.sendMessage(["response": "pong"], replyHandler: nil, errorHandler: { error in
                        print("🔴 [WATCH] Error sending pong: \(error.localizedDescription)")
                    })
                default:
                    self.statusLabel.setText("Unknown: \(command)")
                }
            } else {
                self.statusLabel.setText("Received: \(message)")
            }
        }
    }
    
    // Implement application context receiver as well
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("🔔 [WATCH] Received application context: \(applicationContext)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusLabel.setText("Context Rcvd")
            // Process like a regular message
            if let command = applicationContext["command"] as? String {
                print("🔔 [WATCH] App context command: \(command)")
            }
        }
    }
    
    // Implement user info receiver as another fallback
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("🔔 [WATCH] Received user info: \(userInfo)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusLabel.setText("UserInfo Rcvd")
        }
    }
    
    // Update UI with received metrics
    private func updateMetrics(_ metrics: [String: Any]) {
        if let heartRate = metrics["heartRate"] as? Double {
            heartRateLabel.setText(String(format: "HR: %.0f bpm", heartRate))
        }
        if let distance = metrics["distance"] as? Double {
            distanceLabel.setText(String(format: "Dist: %.2f km", distance))
        }
        if let calories = metrics["calories"] as? Double {
            caloriesLabel.setText(String(format: "Cal: %.0f", calories))
        }
        if let pace = metrics["pace"] as? Double {
            paceLabel.setText(String(format: "Pace: %.2f min/km", pace))
        }
        if let elevation = metrics["elevation"] as? Double {
            elevationLabel.setText(String(format: "Elev: %.0f m", elevation))
        }
    }
    
    // Send heart rate data to iOS app
    func sendHeartRate(_ heartRate: Double) {
        guard let session = session else {
            statusLabel.setText("Not Connected")
            return
        }
        
        switch session.activationState {
        case .activated:
            session.sendMessage(["heartRate": heartRate], replyHandler: nil) { error in
                self.statusLabel.setText("Send Error: \(error.localizedDescription)")
            }
            print("Sent heart rate to iOS app: \(heartRate) bpm")
        default:
            statusLabel.setText("Not Connected")
        }
    }
}

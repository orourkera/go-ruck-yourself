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
            session?.activate()
            statusLabel.setText("Connecting...")
        } else {
            statusLabel.setText("Not Supported")
        }
        
        // Initialize WorkoutManager for HealthKit
        workoutManager = WorkoutManager()
        setupHealthKit()
    }
    
    override func willActivate() {
        super.willActivate()
        // Check session state when view becomes visible
        if let session = session, session.isActivated {
            statusLabel.setText("Connected")
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
        if let error = error {
            statusLabel.setText("Error: \(error.localizedDescription)")
            return
        }
        
        switch activationState {
        case .activated:
            statusLabel.setText("Connected")
        case .inactive:
            statusLabel.setText("Inactive")
        case .notActivated:
            statusLabel.setText("Not Connected")
        @unknown default:
            statusLabel.setText("Unknown State")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle incoming messages from iOS app
        if let command = message["command"] as? String {
            switch command {
            case "workoutStarted":
                statusLabel.setText("Workout Active")
                workoutManager?.startWorkout { error in
                    if let error = error {
                        self.statusLabel.setText("Workout Start Error: \(error.localizedDescription)")
                    }
                }
            case "workoutStopped":
                statusLabel.setText("Workout Ended")
                workoutManager?.endWorkout { error in
                    if let error = error {
                        self.statusLabel.setText("Workout End Error: \(error.localizedDescription)")
                    }
                }
            case "updateMetrics":
                if let metrics = message["metrics"] as? [String: Any] {
                    updateMetrics(metrics)
                }
            default:
                break
            }
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
        guard let session = session, session.isActivated else {
            statusLabel.setText("Not Connected")
            return
        }
        
        session.sendMessage(["heartRate": heartRate], replyHandler: nil) { error in
            self.statusLabel.setText("Send Error: \(error.localizedDescription)")
        }
    }
}

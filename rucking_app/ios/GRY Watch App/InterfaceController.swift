#if os(watchOS)
import WatchKit
import Foundation
import WatchConnectivity
import HealthKit

class InterfaceController: WKInterfaceController, SessionManagerDelegate {
    
    @IBOutlet weak var heartRateLabel: WKInterfaceLabel!
    @IBOutlet weak var distanceLabel: WKInterfaceLabel!
    @IBOutlet weak var caloriesLabel: WKInterfaceLabel!
    @IBOutlet weak var paceLabel: WKInterfaceLabel!
    @IBOutlet weak var elevationLabel: WKInterfaceLabel!
    @IBOutlet weak var statusLabel: WKInterfaceLabel!
    
    private var workoutManager: WorkoutManager?
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Initialize WatchConnectivity session through SessionManager
        // SessionManager.shared.startSession() // Or ensure SessionManager.shared is initialized
        // The line below is removed as SessionManager is the delegate
        
        // Initialize SessionManager if it's not already active
        _ = SessionManager.shared // This will trigger its init if not already done.
        SessionManager.shared.delegate = self // Set InterfaceController as the delegate

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
            let preferMetric = UserDefaults.standard.bool(forKey: "preferMetric")
            if preferMetric {
                distanceLabel.setText("Distance: -- km")
            } else {
                distanceLabel.setText("Distance: -- mi")
            }
        }
        if caloriesLabel == nil {
            print("caloriesLabel outlet is not connected in storyboard!")
        } else {
            caloriesLabel.setText("Calories: --")
        }
        if paceLabel == nil {
            print("paceLabel outlet is not connected in storyboard!")
        } else {
            let preferMetric = UserDefaults.standard.bool(forKey: "preferMetric")
            if preferMetric {
                paceLabel.setText("Pace: -- min/km")
            } else {
                paceLabel.setText("Pace: -- min/mi")
            }
        }
        if elevationLabel == nil {
            print("elevationLabel outlet is not connected in storyboard!")
        } else {
            let preferMetric = UserDefaults.standard.bool(forKey: "preferMetric")
            if preferMetric {
                elevationLabel.setText("Elevation: -- m")
            } else {
                elevationLabel.setText("Elevation: -- ft")
            }
        }
        
        // Initialize WorkoutManager for HealthKit
        workoutManager = WorkoutManager()
        setupHealthKit()
    }
    
    override func willActivate() {
        super.willActivate()
        
        // Don't request permissions again - already done in awake()
        print("[INTERFACE] Watch app activated - permissions already requested in awake()")
    }
    
    override func didDeactivate() {
        super.didDeactivate()
    }
    
    // Setup HealthKit authorization and heart rate handling
    private func setupHealthKit() {
        guard let manager = workoutManager else { 
            print("[INTERFACE_CONTROLLER] ERROR: workoutManager is nil")
            return 
        }
        
        print("[INTERFACE_CONTROLLER] HealthKit available: \(manager.isHealthKitAvailable)")
        if manager.isHealthKitAvailable {
            print("[INTERFACE_CONTROLLER] Requesting HealthKit authorization...")
            manager.requestAuthorization { [weak self] (success, error) in
                guard let self = self else { return }
                if success {
                    // Set handler for heart rate updates
                    manager.setHeartRateHandler { heartRate in
                        DispatchQueue.main.async {
                            self.heartRateLabel.setText(String(format: "HR: %.0f bpm", heartRate))
                            self.sendHeartRate(heartRate)
                        }
                    }
                } else {
                    print("[INTERFACE_CONTROLLER] ❌ HealthKit authorization denied or failed")
                    if let error = error {
                        print("[INTERFACE_CONTROLLER] Authorization error: \(error.localizedDescription)")
                        self.statusLabel.setText("HealthKit Error: \(error.localizedDescription)")
                    } else {
                        self.statusLabel.setText("HealthKit authorization denied")
                    }
                }
            }
        } else {
            print("[INTERFACE_CONTROLLER] ❌ HealthKit not available on this device")
            statusLabel.setText("HealthKit Not Available")
        }
    }
    
    // Update UI with received metrics
    private func updateMetrics(_ metrics: [String: Any]) {
        // Determine unit preference from incoming payload first, fallback to stored default
        let preferMetric: Bool = (metrics["isMetric"] as? Bool) ?? UserDefaults.standard.bool(forKey: "preferMetric")
        // Persist latest preference for future use
        UserDefaults.standard.set(preferMetric, forKey: "preferMetric")
        
        // Update the status label with the duration (timer) value if available
        if let duration = metrics["duration"] as? Int {
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            let seconds = duration % 60
            
            // Format as HH:MM:SS if hours > 0, otherwise MM:SS
            let formattedTime: String
            if hours > 0 {
                formattedTime = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            } else {
                formattedTime = String(format: "%02d:%02d", minutes, seconds)
            }
            
            statusLabel.setText(formattedTime)
        }
        
        if let heartRate = metrics["heartRate"] as? Double {
            heartRateLabel.setText(String(format: "HR: %.0f bpm", heartRate))
        }
        if let distance = metrics["distance"] as? Double {
            if preferMetric {
                distanceLabel.setText(String(format: "Dist: %.2f km", distance))
            } else {
                distanceLabel.setText(String(format: "Dist: %.2f mi", distance))
            }
        }
        if let calories = metrics["calories"] as? Double {
            caloriesLabel.setText(String(format: "Cal: %.0f", calories))
        }
        if let pace = metrics["pace"] as? Double {
            if preferMetric {
                paceLabel.setText(String(format: "Pace: %.2f min/km", pace))
            } else {
                let paceImperial = pace / 0.621371
                paceLabel.setText(String(format: "Pace: %.2f min/mi", paceImperial))
            }
        }
        if let elevationGain = metrics["elevationGain"] as? Double, let elevationLoss = metrics["elevationLoss"] as? Double {
            if preferMetric {
                elevationLabel.setText(String(format: "Elev: +%.0f/-%.0f m", elevationGain, elevationLoss))
            } else {
                let gainFeet = elevationGain * 3.28084
                let lossFeet = elevationLoss * 3.28084
                elevationLabel.setText(String(format: "Elev: +%.0f/-%.0f ft", gainFeet, lossFeet))
            }
        } else if let elevation = metrics["elevation"] as? Double {
            if preferMetric {
                elevationLabel.setText(String(format: "Elev: %.0f m", elevation))
            } else {
                let elevationFeet = elevation * 3.28084
                elevationLabel.setText(String(format: "Elev: %.0f ft", elevationFeet))
            }
        }
    }
    
    // Send heart rate data to iOS app
    func sendHeartRate(_ heartRate: Double) {
        // Use SessionManager.shared to send heart rate data
        SessionManager.shared.sendHeartRate(heartRate)
    }
    
    // MARK: - Command Processing
    private func processCommand(_ command: String, from data: [String: Any]) {
        DispatchQueue.main.async { // Ensure UI updates are on the main thread
            switch command {
            case "startSession":
                self.statusLabel.setText("Session Started")
                // Extract ruck weight if present
                if let ruckWeight = data["ruckWeight"] as? Double {
                    print("🔔 [WATCH UI] Starting session with ruck weight: \(ruckWeight)")
                }
                // Start heart rate monitoring
                self.workoutManager?.startWorkout { error in
                    if let error = error {
                        self.statusLabel.setText("Session Error: \(error.localizedDescription)")
                    } else {
                        print("🔔 [WATCH UI] Heart rate monitoring started")
                    }
                }
                
            case "workoutStarted":
                self.statusLabel.setText("Workout Active")
                // Extract ruck weight if present
                if let ruckWeight = data["ruckWeight"] as? Double {
                    print("🔔 [WATCH UI] Ruck weight: \(ruckWeight)")
                }
                self.workoutManager?.startWorkout { error in
                    if let error = error {
                        self.statusLabel.setText("Workout Error: \(error.localizedDescription)")
                    }
                }
                
            case "workoutStopped":
                self.statusLabel.setText("Workout Ended")
                // Let SessionManager handle the termination logic
                // It will end the workout and terminate the app properly
                SessionManager.shared.delegate?.didReceiveMessage(["command": "workoutStopped"])
                // Also end the local workout manager
                self.workoutManager?.endWorkout { error in
                    if let error = error {
                        print("[WATCH UI] Workout End Error: \(error.localizedDescription)")
                    }
                }
                
            case "updateMetrics":
                print("🔔 [WATCH UI] processCommand: Handling 'updateMetrics'")
                if let metrics = data["metrics"] as? [String: Any] {
                    print("🔔 [WATCH UI] processCommand updateMetrics received: \(metrics)")
                    self.updateMetrics(metrics)
                } else {
                    print("🔴 [WATCH UI] processCommand: Failed to cast 'metrics' from data: \(data)")
                }
                
            case "setSessionId":
                if let sessionId = data["sessionId"] as? Int {
                    self.statusLabel.setText("Session: \(sessionId)")
                }
                
            case "ping":
                self.statusLabel.setText("Ping received!")
                // Optionally, reply back via SessionManager if needed for testing
                // SessionManager.shared.sendMessage(["response": "pong_ui"], replyHandler: nil, errorHandler: { error in
                //     print("🔴 [WATCH UI] Error sending pong: \(error.localizedDescription)")
                // })
                
            default:
                self.statusLabel.setText("Cmd: \(command)")
            }
        }
    }

    // MARK: - SessionManagerDelegate Methods
    
    func sessionDidActivate() {
        DispatchQueue.main.async {
            self.statusLabel.setText("Connected")
            print("🔔 [WATCH UI] SessionManagerDelegate: Session Activated")
        }
    }
    
    func sessionDidDeactivate() {
        DispatchQueue.main.async {
            self.statusLabel.setText("Disconnected")
            print("🔔 [WATCH UI] SessionManagerDelegate: Session Deactivated")
        }
    }
    
    func didReceiveMessage(_ message: [String: Any]) {
        print("🔔 [WATCH UI] SessionManagerDelegate: Received message: \(message)")
        if let command = message["command"] as? String {
            processCommand(command, from: message)
        } else {
            // Handle messages without a 'command' key if necessary
            DispatchQueue.main.async {
                self.statusLabel.setText("Msg Received")
            }
        }
    }
}
#endif

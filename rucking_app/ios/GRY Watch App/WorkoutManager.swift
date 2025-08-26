#if os(watchOS)
import Foundation
import HealthKit
import WatchKit

public protocol WorkoutManagerDelegate: AnyObject {
    func workoutDidEnd()
}

public class WorkoutManager: NSObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateHandler: ((Double) -> Void)?
    private var stepCountHandler: ((Int) -> Void)?
    
    // Delegate to notify about significant workout events
    weak var delegate: WorkoutManagerDelegate?
    
    var isHealthKitAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // Types to read and share via HealthKit
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!
    ]
    
    private let typesToShare: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.workoutType()
    ]
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        print("[WORKOUT_MANAGER] Requesting HealthKit authorization...")
        print("[WORKOUT_MANAGER] Types to read: \(typesToRead)")
        print("[WORKOUT_MANAGER] Types to share: \(typesToShare)")
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            print("[WORKOUT_MANAGER] Authorization result - Success: \(success)")
            if let error = error {
                print("[WORKOUT_MANAGER] Authorization error: \(error.localizedDescription)")
            }
            
            // Check individual permissions
            for type in self.typesToRead {
                let status = self.healthStore.authorizationStatus(for: type)
                print("[WORKOUT_MANAGER] Permission for \(type): \(status.rawValue)")
            }
            
            completion(success, error)
        }
    }
    
    // Start a workout session
    func startWorkout(completion: @escaping (Error?) -> Void) {
        print("[WORKOUT_MANAGER] Starting workout session...")
        
        // Check HealthKit availability first
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[WORKOUT_MANAGER] ERROR: HealthKit not available on this device")
            completion(NSError(domain: "WorkoutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit not available"]))
            return
        }
        
        // Create a workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor
        
        print("[WORKOUT_MANAGER] Created workout configuration: \(configuration)")
        
        do {
            // Create a workout session and builder
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            
            print("[WORKOUT_MANAGER] Created workout session and builder successfully")
            
            // Set the data source
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            // Assign delegates
            session.delegate = self
            builder.delegate = self
            
            // Store references
            self.workoutSession = session
            self.workoutBuilder = builder
            
            print("[WORKOUT_MANAGER] Starting workout activity...")
            
            // Start the workout session first
            session.startActivity(with: Date())
            
            print("[WORKOUT_MANAGER] Starting data collection...")
            
            // Then start data collection
            builder.beginCollection(withStart: Date()) { (success, error) in
                if success {
                    print("[WORKOUT_MANAGER] ✅ Data collection started successfully")
                    
                    // Force heart rate data collection to start immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("[WORKOUT_MANAGER] Requesting initial heart rate update...")
                        self.requestHeartRateUpdate()
                    }
                    
                    // Also request step count update
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("[WORKOUT_MANAGER] Requesting initial step count update...")
                        self.requestStepCountUpdate()
                    }
                } else {
                    print("[WORKOUT_MANAGER] ❌ Data collection failed to start")
                    if let error = error {
                        print("[WORKOUT_MANAGER] Data collection error: \(error.localizedDescription)")
                    }
                }
                completion(error)
            }
        } catch {
            print("[WORKOUT_MANAGER] ❌ Failed to create workout session: \(error.localizedDescription)")
            completion(error)
        }
    }
    
    // Force request heart rate update
    private func requestHeartRateUpdate() {
        print("[WORKOUT_MANAGER] requestHeartRateUpdate() called")
        
        guard let builder = workoutBuilder else { 
            print("[WORKOUT_MANAGER] ERROR: workoutBuilder is nil")
            return 
        }
        
        print("[WORKOUT_MANAGER] Checking for heart rate data...")
        
        // Check if we have any heart rate data available
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            print("[WORKOUT_MANAGER] Got heart rate type, checking statistics...")
            
            if let statistics = builder.statistics(for: heartRateType) {
                print("[WORKOUT_MANAGER] Got statistics: \(statistics)")
                
                if let mostRecent = statistics.mostRecentQuantity() {
                    let heartRate = mostRecent.doubleValue(for: HKUnit(from: "count/min"))
                    print("[WORKOUT_MANAGER] Found recent heart rate: \(heartRate) BPM")
                    
                    if let handler = heartRateHandler {
                        print("[WORKOUT_MANAGER] Calling heart rate handler...")
                        handler(heartRate)
                    } else {
                        print("[WORKOUT_MANAGER] ERROR: Heart rate handler is nil!")
                    }
                } else {
                    print("[WORKOUT_MANAGER] No recent heart rate quantity available")
                }
            } else {
                print("[WORKOUT_MANAGER] No statistics available for heart rate")
            }
        } else {
            print("[WORKOUT_MANAGER] ERROR: Could not get heart rate type")
        }
    }
    
    // Force request step count update
    private func requestStepCountUpdate() {
        print("[WORKOUT_MANAGER] requestStepCountUpdate() called")
        
        guard let builder = workoutBuilder else { 
            print("[WORKOUT_MANAGER] ERROR: workoutBuilder is nil for steps")
            return 
        }
        
        print("[WORKOUT_MANAGER] Checking for step count data...")
        
        // Check if we have any step count data available
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            print("[WORKOUT_MANAGER] Got step count type, checking statistics...")
            
            if let statistics = builder.statistics(for: stepType) {
                print("[WORKOUT_MANAGER] Got step statistics: \(statistics)")
                
                if let mostRecent = statistics.mostRecentQuantity() {
                    let stepCount = Int(mostRecent.doubleValue(for: HKUnit.count()))
                    print("[WORKOUT_MANAGER] Found recent step count: \(stepCount) steps")
                    
                    if let handler = stepCountHandler {
                        print("[WORKOUT_MANAGER] Calling step count handler...")
                        handler(stepCount)
                    } else {
                        print("[WORKOUT_MANAGER] ERROR: Step count handler is nil!")
                    }
                } else {
                    print("[WORKOUT_MANAGER] No recent step count quantity available")
                }
            } else {
                print("[WORKOUT_MANAGER] No statistics available for step count")
            }
        } else {
            print("[WORKOUT_MANAGER] ERROR: Could not get step count type")
        }
    }
    
    // End the current workout session
    func endWorkout(completion: @escaping (Error?) -> Void) {
        guard let session = workoutSession, let builder = workoutBuilder else {
            completion(nil) // No active session to end
            return
        }
        
        // Explicitly end the session first
        session.end()
        
        // End data collection with current date
        builder.endCollection(withEnd: Date()) { (success, error) in
            if let error = error {
                print("[ERROR] Failed to end collection: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            // Finish the workout and save to HealthKit
            builder.finishWorkout { (workout, error) in
                // Clean up references immediately
                self.workoutSession = nil
                self.workoutBuilder = nil
                
                // Log completion for debugging
                print("[WORKOUT] Workout session completely terminated")
                
                completion(error)
            }
        }
    }
    
    // Convenience helper to end a workout without needing a completion handler at call-site
    func stopWorkout() {
        endWorkout { error in
            if let error = error {
                print("[ERROR] Failed to end workout: \(error.localizedDescription)")
            } else {
                // Workout ended successfully
            }
        }
    }
    
    // Set handler for heart rate updates
    func setHeartRateHandler(_ handler: @escaping (Double) -> Void) {
        self.heartRateHandler = handler
    }
    
    // Set handler for step count updates
    func setStepCountHandler(_ handler: @escaping (Int) -> Void) {
        self.stepCountHandler = handler
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WorkoutManager: HKWorkoutSessionDelegate {
    public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("[WORKOUT_MANAGER] Workout session state changed from \(fromState.rawValue) to \(toState.rawValue)")
        
        switch toState {
        case .notStarted:
            print("[WORKOUT_MANAGER] Workout state: Not Started")
        case .prepared:
            print("[WORKOUT_MANAGER] Workout state: Prepared")
        case .running:
            print("[WORKOUT_MANAGER] Workout state: Running - HealthKit data collection should be active")
        case .paused:
            print("[WORKOUT_MANAGER] Workout state: Paused")
        case .ended:
            print("[WORKOUT_MANAGER] Workout state: Ended")
            delegate?.workoutDidEnd()
        @unknown default:
            print("[WORKOUT_MANAGER] Workout state: Unknown (\(toState.rawValue))")
        }
    }
    
    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[WORKOUT_MANAGER] ❌ Workout session failed with error: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        print("[WORKOUT_MANAGER] didCollectDataOf called with types: \(collectedTypes)")
        
        for type in collectedTypes {
            print("[WORKOUT_MANAGER] Processing collected type: \(type)")
            
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { 
                print("[WORKOUT_MANAGER] Failed to get quantityType or statistics for type: \(type)")
                continue 
            }
            
            // Handle heart rate data
            if quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                print("[WORKOUT_MANAGER] Processing heart rate data...")
                
                if let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) {
                    print("[WORKOUT_MANAGER] Got heart rate value: \(value) BPM")
                    
                    if let handler = heartRateHandler {
                        print("[WORKOUT_MANAGER] Calling heart rate handler with value: \(value)")
                        handler(value)
                    } else {
                        print("[WORKOUT_MANAGER] ERROR: Heart rate handler is nil!")
                    }
                } else {
                    print("[WORKOUT_MANAGER] No recent heart rate quantity available")
                }
            }
            
            // Handle step count data
            if quantityType == HKQuantityType.quantityType(forIdentifier: .stepCount) {
                print("[WORKOUT_MANAGER] Processing step count data...")
                
                if let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count()) {
                    let stepCount = Int(value)
                    print("[WORKOUT_MANAGER] Got step count value: \(stepCount) steps")
                    
                    if let handler = stepCountHandler {
                        print("[WORKOUT_MANAGER] Calling step count handler with value: \(stepCount)")
                        handler(stepCount)
                    } else {
                        print("[WORKOUT_MANAGER] ERROR: Step count handler is nil!")
                    }
                } else {
                    print("[WORKOUT_MANAGER] No recent step count quantity available")
                }
            }
        }
    }
    
    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle events if needed
    }
}
#endif

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
    
    // Delegate to notify about significant workout events
    weak var delegate: WorkoutManagerDelegate?
    
    var isHealthKitAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // Types to read and share via HealthKit
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    ]
    
    private let typesToShare: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.workoutType()
    ]
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            completion(success, error)
        }
    }
    
    // Start a workout session
    func startWorkout(completion: @escaping (Error?) -> Void) {
        // Create a workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor
        
        do {
            // Create a workout session and builder
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            
            // Set the data source
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            // Assign delegates
            session.delegate = self
            builder.delegate = self
            
            // Store references
            self.workoutSession = session
            self.workoutBuilder = builder
            
            // Start the workout session first
            session.startActivity(with: Date())
            
            // Then start data collection
            builder.beginCollection(withStart: Date()) { (success, error) in
                if success {
                    // Force heart rate data collection to start immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        // Manually trigger data collection check
                        self.requestHeartRateUpdate()
                    }
                }
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    // Force request heart rate update
    private func requestHeartRateUpdate() {
        guard let builder = workoutBuilder else { return }
        
        // Check if we have any heart rate data available
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let statistics = builder.statistics(for: heartRateType),
           let mostRecent = statistics.mostRecentQuantity() {
            let heartRate = mostRecent.doubleValue(for: HKUnit(from: "count/min"))
            heartRateHandler?(heartRate)
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
}

// MARK: - HKWorkoutSessionDelegate
extension WorkoutManager: HKWorkoutSessionDelegate {
    public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // Handle state changes if needed
        if toState == .ended {
            delegate?.workoutDidEnd()
        }
    }
    
    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Handle errors if needed
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
        }
    }
    
    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle events if needed
    }
}
#endif

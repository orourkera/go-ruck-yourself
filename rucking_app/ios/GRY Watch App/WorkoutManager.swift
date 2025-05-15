#if os(watchOS)
import Foundation
import HealthKit

class WorkoutManager: NSObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateHandler: ((Double) -> Void)?
    
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
            
            // Start the workout session and builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { (success, error) in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    // End the current workout session
    func endWorkout(completion: @escaping (Error?) -> Void) {
        guard let session = workoutSession, let builder = workoutBuilder else {
            completion(nil) // No active session to end
            return
        }
        
        session.end()
        builder.endCollection(withEnd: Date()) { (success, error) in
            if let error = error {
                completion(error)
                return
            }
            
            builder.finishWorkout { (workout, error) in
                self.workoutSession = nil
                self.workoutBuilder = nil
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
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // Handle state changes if needed
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Handle errors if needed
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            
            // Handle heart rate data
            if quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                if let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")),
                   let handler = heartRateHandler {
                    handler(value)
                }
            }
        }
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle events if needed
    }
}
#endif

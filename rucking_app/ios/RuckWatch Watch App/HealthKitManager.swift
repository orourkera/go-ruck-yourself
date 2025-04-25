import Foundation
import HealthKit

class HealthKitManager {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery? // Changed to specific type
    
    private init() {}
    
    // Health data types we'll use
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.workoutType()
    ]
    
    private let typesToWrite: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.workoutType()
    ]
    
    func requestAuthorization() {
        // Request HealthKit authorization
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { (success: Bool, error: Error?) in
            if let error = error {
                print("HealthKit authorization error: \(error.localizedDescription)")
                return
            }
            
            if success {
                print("HealthKit authorization granted")
            } else {
                print("HealthKit authorization denied")
            }
        }
    }
    
    // Start continuous heart rate monitoring
    func startHeartRateMonitoring(completion: @escaping (Double?) -> Void) {
        stopHeartRateMonitoring()
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        // Create a predicate to get samples from now onwards
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        
        // Create the query
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { (query: HKAnchoredObjectQuery, samples: [HKSample]?, deletedObjects: [HKDeletedObject]?, anchor: HKQueryAnchor?, error: Error?) in
            guard error == nil else {
                print("Heart rate query error: \(error!.localizedDescription)")
                return
            }
            
            self.processHeartRateSamples(samples, completion: completion)
        }
        
        // Get updates for future samples
        if let query = heartRateQuery {
            query.updateHandler = { (query: HKAnchoredObjectQuery, samples: [HKSample]?, deletedObjects: [HKDeletedObject]?, anchor: HKQueryAnchor?, error: Error?) in
                guard error == nil else {
                    print("Heart rate update error: \(error!.localizedDescription)")
                    return
                }
                
                self.processHeartRateSamples(samples, completion: completion)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func processHeartRateSamples(_ samples: [HKSample]?, completion: @escaping (Double?) -> Void) {
        guard let samples = samples as? [HKQuantitySample] else { return }
        
        // Find the most recent sample
        guard let sample = samples.max(by: { $0.startDate < $1.startDate }) else { return }
        
        // Get the heart rate in BPM
        let heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        completion(heartRate)
    }
    
    func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
    
    // Save a workout to HealthKit
    func saveWorkout(startDate: Date, endDate: Date, distance: Double, calories: Double, ruckWeight: Double) {
        // Create a hiking workout
        let workoutConfiguration = HKWorkoutConfiguration()
        workoutConfiguration.activityType = .hiking
        workoutConfiguration.locationType = .outdoor
        
        // Create the workout
        let workout = HKWorkout(
            activityType: .hiking,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distance),
            metadata: ["ruckWeightKg": ruckWeight]
        )
        
        // Save the workout
        healthStore.save(workout) { (success: Bool, error: Error?) in
            if let error = error {
                print("Error saving workout: \(error.localizedDescription)")
                return
            }
            
            if success {
                print("Workout saved successfully")
                
                // Save detailed samples for distance and calories
                self.saveWorkoutSamples(workout: workout, distance: distance, calories: calories, startDate: startDate, endDate: endDate)
            }
        }
    }
    
    // Save detailed workout samples
    private func saveWorkoutSamples(workout: HKWorkout, distance: Double, calories: Double, startDate: Date, endDate: Date) {
        // Create distance sample
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distance)
        let distanceSample = HKQuantitySample(
            type: distanceType,
            quantity: distanceQuantity,
            start: startDate,
            end: endDate
        )
        
        // Create calories sample
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let caloriesQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let caloriesSample = HKQuantitySample(
            type: caloriesType,
            quantity: caloriesQuantity,
            start: startDate,
            end: endDate
        )
        
        // Add samples to the workout
        healthStore.add([distanceSample, caloriesSample], to: workout) { (success: Bool, error: Error?) in
            if let error = error {
                print("Error saving workout samples: \(error.localizedDescription)")
                return
            }
            
            if success {
                print("Workout samples saved successfully")
            }
        }
    }
}

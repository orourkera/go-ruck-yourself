import Foundation
import HealthKit
import Combine

@available(iOS 13.0, watchOS 9.0, *)
class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKQuery?
    private var heartRateObserver: Any?
    
    @Published var heartRate: Double = 0.0
    
    // Delegate to receive heart rate updates
    weak var delegate: HealthKitDelegate?
    
    override init() {
        super.init()
        requestAuthorization()
    }
    
    func requestAuthorization() {
        // Define the health data types we want to read
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        // Request authorization
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if !success {
                print("HealthKit authorization was not granted: \(String(describing: error))")
            } else {
                print("HealthKit authorization granted")
            }
        }
    }
    
    // Start monitoring heart rate
    func startHeartRateMonitoring() {
        // Get the heart rate type
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("Heart Rate Type is not available")
            return
        }
        
        // Create a predicate to get recent heart rate samples
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: nil, options: .strictEndDate)
        
        // Set up the heart rate observer
        let heartRateObserver = HKObserverQuery(sampleType: heartRateType, predicate: predicate) { [weak self] query, completionHandler, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error with heart rate observer: \(error.localizedDescription)")
                return
            }
            
            // Perform the actual heart rate query
            self.performHeartRateQuery()
            
            // Call the completion handler
            completionHandler()
        }
        
        // Execute the query
        healthStore.execute(heartRateObserver)
        
        // Also execute a heart rate query to get initial data
        performHeartRateQuery()
        
        // Save the reference to the observer
        self.heartRateObserver = heartRateObserver
    }
    
    // Stop monitoring heart rate
    func stopHeartRateMonitoring() {
        if let heartRateObserver = self.heartRateObserver {
            healthStore.stop(heartRateObserver as! HKQuery)
            self.heartRateObserver = nil
        }
        
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
    
    // Perform heart rate query
    private func performHeartRateQuery() {
        // Get the heart rate type
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("Heart Rate Type is not available")
            return
        }
        
        // Create the query for recent heart rate samples
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let self = self else { return }
            
            guard let samples = samples as? [HKQuantitySample], let sample = samples.first else {
                if let error = error {
                    print("Error querying heart rate: \(error.localizedDescription)")
                }
                return
            }
            
            // Get the heart rate value in beats per minute
            let heartRateValue = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
            
            // Update the heart rate on the main thread
            DispatchQueue.main.async {
                // Update the published property
                self.heartRate = heartRateValue
                
                // Notify via delegate
                self.delegate?.heartRateUpdated(heartRate: heartRateValue)
            }
        }
        
        // Execute the query
        healthStore.execute(query)
        
        // Save reference to the query
        self.heartRateQuery = query
    }
    
    // Get workout duration, distance, and calories (called at the end of a workout)
    func getWorkoutStats(startDate: Date, completion: @escaping (Double, Double, Double) -> Void) {
        var duration = 0.0
        var distance = 0.0
        var calories = 0.0
        
        let endDate = Date()
        duration = endDate.timeIntervalSince(startDate)
        
        // Query for distance and calories
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
              let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(duration, 0, 0)
            return
        }
        
        // Define predicate for the time range
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        // Query for distance
        let distanceQuery = HKStatisticsQuery(
            quantityType: distanceType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let self = self else { return }
            
            if let result = result, let sum = result.sumQuantity() {
                // Convert to meters
                distance = sum.doubleValue(for: HKUnit.meter())
            }
            
            // Query for calories
            let caloriesQuery = HKStatisticsQuery(
                quantityType: caloriesType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let result = result, let sum = result.sumQuantity() {
                    // Convert to calories
                    calories = sum.doubleValue(for: HKUnit.kilocalorie())
                }
                
                // Call the completion handler with all stats
                DispatchQueue.main.async {
                    completion(duration, distance, calories)
                }
            }
            
            self.healthStore.execute(caloriesQuery)
        }
        
        healthStore.execute(distanceQuery)
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
        healthStore.save(workout) { [weak self] success, error in
            guard let self = self else { return }
            
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
        healthStore.add([distanceSample, caloriesSample], to: workout) { success, error in
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

// Protocol for heart rate updates
protocol HealthKitDelegate: AnyObject {
    func heartRateUpdated(heartRate: Double)
}

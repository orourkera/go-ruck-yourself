import HealthKit

class WorkoutManager: NSObject {
    
    private let healthStore = HKHealthStore()
    private var workout: HKWorkout?
    private var activeQueries = [HKQuery]()
    private var heartRateHandler: ((Double) -> Void)?
    
    // Check if HealthKit data is available on this device
    var isHealthKitAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard isHealthKitAvailable else {
            completion(false, NSError(domain: "WorkoutManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."]))
            return
        }
        
        let typesToShare: Set = [HKObjectType.workoutType()]
        let typesToRead: Set = [HKObjectType.quantityType(forIdentifier: .heartRate)!]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            completion(success, error)
        }
    }
    
    // Start a workout session
    func startWorkout(completion: @escaping (Error?) -> Void) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking // Using walking as a proxy for rucking
        configuration.locationType = .outdoor
        
        healthStore.startWorkout(with: configuration) { [weak self] (workout, error) in
            guard let self = self else { return }
            if let error = error {
                completion(error)
                return
            }
            
            self.workout = workout
            self.startHeartRateMonitoring()
            completion(nil)
        }
    }
    
    // End the current workout session
    func endWorkout(completion: @escaping (Error?) -> Void) {
        guard let workout = workout else {
            completion(NSError(domain: "WorkoutManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active workout to end."]))
            return
        }
        
        healthStore.end(workout) { [weak self] (error) in
            guard let self = self else { return }
            if let error = error {
                completion(error)
                return
            }
            
            self.workout = nil
            self.stopAllQueries()
            completion(nil)
        }
    }
    
    // Set handler for heart rate updates
    func setHeartRateHandler(_ handler: @escaping (Double) -> Void) {
        self.heartRateHandler = handler
    }
    
    // Start monitoring heart rate
    private func startHeartRateMonitoring() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        let query = HKAnchoredObjectQuery(type: heartRateType, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] (query, samples, deletedObjects, newAnchor, error) in
            guard let self = self else { return }
            if let error = error {
                print("Heart rate query failed: \(error.localizedDescription)")
                return
            }
            
            if let heartRateSamples = samples as? [HKQuantitySample] {
                self.processHeartRateSamples(heartRateSamples)
            }
        }
        
        query.updateHandler = { [weak self] (query, samples, deletedObjects, newAnchor, error) in
            guard let self = self else { return }
            if let error = error {
                print("Heart rate update failed: \(error.localizedDescription)")
                return
            }
            
            if let heartRateSamples = samples as? [HKQuantitySample] {
                self.processHeartRateSamples(heartRateSamples)
            }
        }
        
        activeQueries.append(query)
        healthStore.execute(query)
    }
    
    // Process received heart rate samples
    private func processHeartRateSamples(_ samples: [HKQuantitySample]) {
        guard let handler = heartRateHandler else { return }
        
        for sample in samples {
            let heartRateUnit = HKUnit(from: "count/min")
            let heartRate = sample.quantity.doubleValue(for: heartRateUnit)
            handler(heartRate)
        }
    }
    
    // Stop all active queries
    private func stopAllQueries() {
        for query in activeQueries {
            healthStore.stop(query)
        }
        activeQueries.removeAll()
    }
}

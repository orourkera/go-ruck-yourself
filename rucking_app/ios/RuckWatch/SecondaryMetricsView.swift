import SwiftUI

struct SecondaryMetricsView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Heart Rate
            MetricCard(
                title: "HEART RATE",
                value: formatHeartRate(sessionManager.heartRate)
            )
            .frame(maxWidth: .infinity)
            
            // Pace
            MetricCard(
                title: "PACE",
                value: formatPace(sessionManager.pace)
            )
            .frame(maxWidth: .infinity)
            
            // Calories
            MetricCard(
                title: "CALORIES",
                value: formatCalories(sessionManager.caloriesBurned)
            )
            .frame(maxWidth: .infinity)
            
            // Ruck weight
            MetricCard(
                title: "RUCK WEIGHT",
                value: formatWeight(sessionManager.ruckWeight)
            )
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    private func formatHeartRate(_ heartRate: Double?) -> String {
        guard let hr = heartRate else { return "--" }
        return "\(Int(hr)) BPM"
    }
    
    private func formatPace(_ pace: Double) -> String {
        if pace <= 0 {
            return "--:--"
        }
        
        // pace is in min/km
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    private func formatCalories(_ calories: Double) -> String {
        return "\(Int(calories))"
    }
    
    private func formatWeight(_ weight: Double) -> String {
        return String(format: "%.1f kg", weight)
    }
}

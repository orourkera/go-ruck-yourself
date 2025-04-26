//
//  SecondaryMetricsView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

struct SecondaryMetricsView: View {
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Title at the top, left-aligned, positioned with the time
                Text("GRY")
                    .font(.system(size: 24))
                    .bold()
                    .padding(.top, 2) // Small positive padding instead of negative
                
                // Grid layout for metrics
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    // Heart Rate
                    MetricCard(
                        title: "HEART RATE",
                        value: formatHeartRate(sessionManager.heartRate)
                    )
                    
                    // Pace
                    MetricCard(
                        title: "PACE",
                        value: formatPace(sessionManager.pace)
                    )
                    
                    // Calories
                    MetricCard(
                        title: "CALORIES",
                        value: formatCalories(sessionManager.calories)
                    )
                    
                    // Ruck weight
                    MetricCard(
                        title: "RUCK WEIGHT",
                        value: formatWeight(sessionManager.ruckWeight)
                    )
                }
                .padding(.top, 2)
            }
            .padding(.horizontal)
            .padding(.top, 0)
        }
        .edgesIgnoringSafeArea(.top) // Extend content to the very top of the screen
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

//
//  SessionReviewView.swift
//  RuckWatch Watch App
//
//  Created on 26/4/25.
//

import SwiftUI

@available(watchOS 9.0, *)
struct SessionReviewView: View {
    let duration: TimeInterval
    let distance: Double
    let calories: Double
    let avgHeartRate: Double
    let ruckWeight: Double
    let elevationGain: Double
    
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text("Session Complete")
                    .font(.system(size: 20))
                    .fontWeight(.bold)
                    .padding(.top, 2)
                
                // Grid layout for metrics summary
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    // Row 1: Time and Heart Rate
                    MetricCard(
                        title: "TIME",
                        value: formatDuration(duration)
                    )
                    
                    MetricCard(
                        title: "AVG HR",
                        value: formatHeartRate(avgHeartRate)
                    )
                    
                    // Row 2: Calories and Distance
                    MetricCard(
                        title: "CALORIES",
                        value: formatCalories(calories)
                    )
                    
                    MetricCard(
                        title: "DISTANCE",
                        value: formatDistance(distance)
                    )
                    
                    // Row 3: Pace and Elevation
                    MetricCard(
                        title: "AVG PACE",
                        value: formatPace(duration, distance)
                    )
                    
                    MetricCard(
                        title: "ELEVATION",
                        value: formatElevation(elevationGain)
                    )
                }
                .padding(.top, 2)
                
                // Done button
                Button {
                    sessionManager.dismissSessionReview()
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color("ArmyGreen"))
                        .cornerRadius(12)
                }
                .padding(.top, 12)
                .padding(.bottom)
            }
            .padding(.horizontal)
        }
        .ignoresSafeArea(edges: .top)
    }
    
    // Formatting utility functions
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func formatDistance(_ distance: Double) -> String {
        // Convert meters to kilometers
        let km = distance / 1000.0
        return String(format: "%.2f km", km)
    }
    
    private func formatCalories(_ calories: Double) -> String {
        return String(format: "%.0f", calories)
    }
    
    private func formatHeartRate(_ heartRate: Double) -> String {
        return String(format: "%.0f BPM", heartRate)
    }
    
    private func formatPace(_ duration: TimeInterval, _ distance: Double) -> String {
        if distance <= 0 {
            return "--:--"
        }
        
        // Calculate pace in minutes per km
        let distanceInKm = distance / 1000.0
        let totalMinutes = duration / 60.0
        let paceMinPerKm = totalMinutes / distanceInKm
        
        let minutes = Int(paceMinPerKm)
        let seconds = Int((paceMinPerKm - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        return String(format: "%.1f kg", weight)
    }
    
    private func formatElevation(_ elevation: Double) -> String {
        return String(format: "%.0f m", elevation)
    }
}

//
//  PrimaryMetricsView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

@available(watchOS 9.0, *)
struct PrimaryMetricsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title at the top, left-aligned, positioned with the time
                Text("GRY")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color("ArmyGreen"))
                    .padding(.top, 0)
                    .padding(.bottom, 8)
                
                // Grid layout for metrics (2x2)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    // Row 1: Time and Heart Rate
                    MetricCard(
                        title: "TIME", 
                        value: formatDuration(sessionManager.elapsedDuration)
                    )
                    
                    // Heart Rate
                    MetricCard(
                        title: "HEART RATE",
                        value: formatHeartRate(sessionManager.heartRate)
                    )
                    
                    // Row 2: Calories and Distance
                    MetricCard(
                        title: "CALORIES", 
                        value: formatCalories(sessionManager.calories)
                    )
                    
                    MetricCard(
                        title: "DISTANCE", 
                        value: formatDistance(sessionManager.distance)
                    )
                    
                    // Row 3: Pace and Elevation
                    MetricCard(
                        title: "PACE",
                        value: formatPace(sessionManager.pace)
                    )
                    
                    MetricCard(
                        title: "ELEVATION", 
                        value: formatElevation(sessionManager.elevationGain)
                    )
                }
                .padding(.top, 2)
                
                // Control buttons
                HStack(spacing: 24) {
                    Button {
                        if sessionManager.isPaused {
                            sessionManager.resumeSession()
                        } else {
                            sessionManager.pauseSession()
                        }
                    } label: {
                        if sessionManager.isPaused {
                            Image(systemName: "play.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color("ArmyGreen"))
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        sessionManager.endSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                
                .padding(.horizontal)
                .padding(.top, 0)
            }
            .ignoresSafeArea(.all, edges: .top) // Modern SwiftUI syntax for ignoring safe area
        }
    }
    
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
    
    private func formatElevation(_ elevation: Double) -> String {
        return String(format: "%.0f m", elevation)
    }
    
    private func formatHeartRate(_ heartRate: Double) -> String {
        return String(format: "%.0f BPM", heartRate)
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
}

struct MetricCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .fontWeight(.medium)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
    }
}

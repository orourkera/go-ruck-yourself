//
//  PrimaryMetricsView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

@available(iOS 13.0, watchOS 9.0, *)
struct PrimaryMetricsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Title at the top, left-aligned, positioned with the time
                Text("GRY")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color("ArmyGreen"))
                    .padding(.top, 2)
                
                // Grid layout for metrics (2x2)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    // Time
                    MetricCard(
                        title: "TIME", 
                        value: formatDuration(sessionManager.elapsedDuration)
                    )
                    
                    // Distance
                    MetricCard(
                        title: "DISTANCE", 
                        value: formatDistance(sessionManager.distance)
                    )
                    
                    // Calories
                    MetricCard(
                        title: "CALORIES", 
                        value: formatCalories(sessionManager.calories)
                    )
                    
                    // Elevation
                    MetricCard(
                        title: "ELEVATION", 
                        value: formatElevation(sessionManager.elevationGain)
                    )
                }
                .padding(.top, 2)
                
                // Control buttons
                HStack(spacing: 12) {
                    Button {
                        if sessionManager.isPaused {
                            sessionManager.resumeSession()
                        } else {
                            sessionManager.pauseSession()
                        }
                    } label: {
                        Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20))
                            .foregroundColor(sessionManager.isPaused ? .green : .orange)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    
                    Button {
                        sessionManager.endSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Bottom buttons
                HStack {
                    Button {
                        if sessionManager.isPaused {
                            sessionManager.resumeSession()
                        } else {
                            sessionManager.pauseSession()
                        }
                    } label: {
                        Text(sessionManager.isPaused ? "Resume" : "Pause")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(sessionManager.isPaused ? .green : .orange)
                    
                    Button {
                        sessionManager.endSession()
                    } label: {
                        Text("End")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.bottom)
            }
            .padding(.horizontal)
            .padding(.top, 0)
        }
        .ignoresSafeArea(.all, edges: .top) // Modern SwiftUI syntax for ignoring safe area
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

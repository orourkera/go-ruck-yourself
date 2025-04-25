//
//  PrimaryMetricsView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

struct PrimaryMetricsView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Time
            MetricCard(title: "TIME", value: formatDuration(sessionManager.sessionDuration))
                .frame(maxWidth: .infinity)
            
            // Distance
            MetricCard(title: "DISTANCE", value: formatDistance(sessionManager.distance))
                .frame(maxWidth: .infinity)
            
            // Control buttons
            HStack(spacing: 12) {
                Button(action: {
                    if sessionManager.isPaused {
                        sessionManager.resumeSession()
                    } else {
                        sessionManager.pauseSession()
                    }
                }) {
                    Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20))
                        .foregroundColor(sessionManager.isPaused ? .green : .orange)
                }
                .buttonStyle(.plain)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 40, height: 40)
                )
                
                Button(action: {
                    sessionManager.endSession()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 40, height: 40)
                )
            }
            .padding(.top, 8)
        }
        .padding()
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

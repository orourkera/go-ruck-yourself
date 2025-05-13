//
//  ContentView.swift
//  GRY Watch App
//
//  Created by Rory on 6/5/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Green left-aligned "GRY" title
            Text("GRY")
                .font(.headline)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            
            // Full-width timer (status text contains the timer now)
            Text(sessionManager.statusText)
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
                .multilineTextAlignment(.center)
            
            // 2x2 Grid for metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Distance
                VStack(alignment: .center, spacing: 0) {
                    Text("DIST")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.distance)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                
                // Pace
                VStack(alignment: .center, spacing: 0) {
                    Text("PACE")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.pace)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                
                // Calories
                VStack(alignment: .center, spacing: 0) {
                    Text("CAL")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.caloriesText)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                
                // Elevation
                VStack(alignment: .center, spacing: 0) {
                    Text("ELEV")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.elevationText)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .padding(.top, 2)
            
            // Heart rate at the bottom
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.body)
                Text(sessionManager.heartRateText)
                    .font(.system(size: 20, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
        .padding(10)
        .onAppear {
            sessionManager.startSession()
        }
    }
}

#Preview {
    ContentView()
}

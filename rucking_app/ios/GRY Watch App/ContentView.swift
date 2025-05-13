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
                .padding(.vertical, 4)
                .multilineTextAlignment(.center)
            
            // 2x2 Grid for metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Distance
                VStack(alignment: .center, spacing: 2) {
                    Text("DIST")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.distance)
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                
                // Pace
                VStack(alignment: .center, spacing: 2) {
                    Text("PACE")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.pace)
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                
                // Calories
                VStack(alignment: .center, spacing: 2) {
                    Text("CAL")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.caloriesText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity)
                
                // Elevation
                VStack(alignment: .center, spacing: 2) {
                    Text("ELEV")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(sessionManager.elevationText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
            
            // Heart rate at the bottom
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text(sessionManager.heartRateText)
                    .font(.system(size: 14))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
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

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
        ZStack {
            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Green left-aligned "GRY" title
                    Text("GRY")
                        .font(.headline)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                    
                    // Full-width timer (only show timer when active, otherwise show placeholder)
                    Text(sessionManager.statusText.contains("Connect") ? "--" : sessionManager.statusText)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    // 2x2 Grid for metrics - with larger cells
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        // Distance - Full-size Metric Box
                        VStack(alignment: .center, spacing: 2) {
                            Text("DISTANCE")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                            Text(sessionManager.distance)
                                .font(.system(size: 24, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .padding(3)
                        
                        // Pace - Full-size Metric Box
                        VStack(alignment: .center, spacing: 2) {
                            Text("PACE")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                            Text(sessionManager.pace)
                                .font(.system(size: 24, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .padding(3)
                        
                        // Calories - Full-size Metric Box
                        VStack(alignment: .center, spacing: 2) {
                            Text("CALORIES")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                            Text(sessionManager.caloriesText)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .padding(3)
                        
                        // Elevation - Full-size Metric Box
                        VStack(alignment: .center, spacing: 2) {
                            Text("ELEVATION")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                            Text(sessionManager.elevationText)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.cyan)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .padding(3)
                    }
                    .padding(.top, 5)
                    
                    // Heart rate and control buttons section
                    VStack(spacing: 10) {
                        // Heart rate indicator
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                            Text(sessionManager.heartRateText)
                                .font(.system(size: 24, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        
                        // Play/Pause button (only shown if session is active)
                        if sessionManager.isSessionActive {
                            Button(action: {
                                sessionManager.togglePauseResume()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(sessionManager.isPaused ? .green : .orange)
                                    
                                    Text(sessionManager.isPaused ? "Resume" : "Pause")
                                        .font(.headline)
                                        .foregroundColor(sessionManager.isPaused ? .green : .orange)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 5)
                }
                .padding(12)
            }
            
            // Overlay the split notification when active
            if sessionManager.showingSplitNotification {
                // Semi-transparent overlay for the split notification
                VStack(spacing: 8) {
                    Text("Split Complete!")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Distance:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(sessionManager.splitDistance)
                                .font(.body)
                                .foregroundColor(.green)
                        }
                        
                        HStack {
                            Text("Time:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(sessionManager.splitTime)
                                .font(.body)
                                .foregroundColor(.green)
                        }
                        
                        Divider()
                            .background(Color.gray.opacity(0.5))
                        
                        HStack {
                            Text("Total:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(sessionManager.totalDistance)
                                .font(.body)
                        }
                        
                        HStack {
                            Text("Total Time:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(sessionManager.totalTime)
                                .font(.body)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(16)
                .background(Color.black.opacity(0.85))
                .cornerRadius(12)
                .shadow(radius: 5)
                .padding(12)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: sessionManager.showingSplitNotification)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear {
            sessionManager.startSession()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

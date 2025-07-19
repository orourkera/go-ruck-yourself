#if os(watchOS)
//
//  ContentView.swift
//  GRY Watch App
//
//  Created by Rory on 6/5/25.
//

import SwiftUI
import WatchConnectivity
import HealthKit  // Added in case there's a dependency

// If the watch app is a separate module, it might need to be imported
#if canImport(GRY_Watch_App)
import GRY_Watch_App
#endif

struct ContentView: View {
    // Use the singleton instance so UI and connectivity logic share the same state
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        ZStack {
            // Main content
            if sessionManager.isSessionActive {
                CompactWorkoutView()
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Text("Ruck")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundColor(.green)
                            .fixedSize(horizontal: true, vertical: false) // Prevent text truncation
                            .padding(.leading, 4) // Add some left padding
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    
                    Spacer()
                    
                    Text("Start a ruck on your phone to begin.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Overlay the split notification when active - full screen version
            if sessionManager.showingSplitNotification {
                // Full-screen overlay that covers everything
                ZStack {
                    // Black background covering full screen
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    // Simplified content
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Text("Split Complete!")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 20)
                        
                        // Split time - prominent and centered
                        Text(sessionManager.splitTime)
                            .font(.system(size: 46, weight: .bold))
                            .foregroundColor(.green)
                        
                        // Split metrics - calories and elevation
                        HStack(spacing: 20) {
                            if !sessionManager.splitCalories.isEmpty {
                                VStack(spacing: 4) {
                                    Text("Calories")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(sessionManager.splitCalories)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            if !sessionManager.splitElevation.isEmpty {
                                VStack(spacing: 4) {
                                    Text("Elevation")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(sessionManager.splitElevation)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                        .padding(.top, 16)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: sessionManager.showingSplitNotification)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear {
            sessionManager.startSession()
        }
    }
    
    // Extracted view for active session UI
    private var activeSessionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Full-width timer container - ensure it takes full width
                HStack {
                    Spacer()
                    Text(sessionManager.statusText)
                        .font(.custom("Bangers-Regular", size: 32))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                }
                .frame(maxWidth: .infinity) // Ensure full width
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                
                // Pace display (below timer)
                Text(sessionManager.pace)
                    .font(.footnote) // Smaller font
                    .foregroundColor(.gray) // Gray color
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 5) // Add some padding below pace

                // 2x2 Grid for metrics - with larger cells
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                    // Distance - Full-size Metric Box
                    VStack(alignment: .center, spacing: 2) {
                        Text(sessionManager.isMetric ? "DISTANCE" : "DISTANCE")
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
                    .padding(1)
                    
                    // Heart Rate - Full-size Metric Box (moved into grid)
                    VStack(alignment: .center, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("HR") // Changed from HEART RATE
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 2)
                        Text(sessionManager.heartRateText)
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundColor(.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .padding(1)
                    
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
                    .padding(1)
                    
                    // Elevation - Full-size Metric Box
                    VStack(alignment: .center, spacing: 2) {
                        Text(sessionManager.isMetric ? "ELEVATION" : "ELEVATION")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.top, 2)
                        Text(sessionManager.elevationText)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(red: 0, green: 0.9, blue: 0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .padding(1)
                }
                .padding(.top, 2)
                
                // Control buttons section (Heart rate display removed from here)
                VStack(spacing: 2) {
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
                .padding(.top, 2)
            }
            .padding(6)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

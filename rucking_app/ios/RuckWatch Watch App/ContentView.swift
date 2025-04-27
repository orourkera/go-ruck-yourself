//
//  ContentView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

@available(iOS 13.0, watchOS 9.0, *)
struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedTab: Tab = .primary
    
    enum Tab {
        case primary, secondary
    }
    
    var body: some View {
        ZStack {
            if sessionManager.isShowingSessionReview, let summary = sessionManager.sessionSummary {
                SessionReviewView(
                    duration: summary.duration,
                    distance: summary.distance,
                    calories: summary.calories,
                    avgHeartRate: summary.avgHeartRate,
                    ruckWeight: summary.ruckWeight,
                    elevationGain: summary.elevationGain
                )
                .transition(.opacity)
                .onDisappear {
                    sessionManager.isShowingSessionReview = false
                    sessionManager.sessionSummary = nil
                }
            } else if sessionManager.isSessionActive {
                TabView(selection: $selectedTab) {
                    PrimaryMetricsView()
                        .tag(Tab.primary)
                    
                    SecondaryMetricsView()
                        .tag(Tab.secondary)
                }
                .tabViewStyle(.page)
            } else {
                StartSessionView()
            }
        }
    }
}

@available(iOS 14.0, watchOS 9.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

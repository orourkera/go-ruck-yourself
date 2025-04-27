//
//  ContentView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

@available(watchOS 9.0, *)
struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
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
                .onDisappear {
                    sessionManager.isShowingSessionReview = false
                    sessionManager.sessionSummary = nil
                }
            } else if sessionManager.isSessionActive {
                PrimaryMetricsView()
            } else {
                StartSessionView()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

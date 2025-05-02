//
//  GRYWatchApp.swift
//  GRY Watch App
//
//  Created by Rory on 29/4/25.
//

import SwiftUI

@available(iOS 14.0, watchOS 9.0, *)
@main
struct GRYWatchApp: App {
    // Use the singleton so all views observe same instance
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if sessionManager.isSessionActive {
                    PrimaryMetricsView()
                } else {
                    StartSessionView()
                }
            }
            .environmentObject(sessionManager)
        }
    }
    
    init() {
        // Additional init if needed
    }
}

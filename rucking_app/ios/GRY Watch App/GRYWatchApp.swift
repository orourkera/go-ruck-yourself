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
    @StateObject private var sessionManager = SessionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
    }
    
    init() {
        // Initialize any services here if needed
    }
}

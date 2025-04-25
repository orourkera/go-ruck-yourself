//
//  RuckWatchApp.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

@main
struct RuckWatchApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    init() {
        // Initialize any services here if needed
    }
}

//
//  ContentView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var selectedTab: Tab = .primary
    
    enum Tab {
        case primary, secondary
    }
    
    var body: some View {
        if sessionManager.isSessionActive {
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

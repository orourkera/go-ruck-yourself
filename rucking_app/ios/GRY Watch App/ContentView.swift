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
        VStack {
            Text("GRY Watch App")
                .font(.headline)
                .padding(.bottom, 10)
            
            Text(sessionManager.statusText)
                .font(.subheadline)
                .foregroundColor(sessionManager.statusText.contains("Connected") ? .green : .red)
                .padding(.bottom, 5)
            
            Text(sessionManager.heartRateText)
                .font(.title2)
                .padding(.bottom, 5)
            
            Spacer()
        }
        .padding()
        .onAppear {
            sessionManager.startSession()
        }
    }
}

#Preview {
    ContentView()
}

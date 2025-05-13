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
                .padding(.bottom, 5)
            
            Text(sessionManager.statusText)
                .font(.caption)
                .foregroundColor(sessionManager.statusText.contains("Connected") ? .green : .red)
                .padding(.bottom, 3)
            
            Text(sessionManager.heartRateText)
                .font(.title3)
                .padding(.bottom, 3)
            
            Text(sessionManager.caloriesText)
                .font(.body)
                .foregroundColor(.orange)
                .padding(.bottom, 3)
            
            Text(sessionManager.elevationText)
                .font(.caption)
                .foregroundColor(.cyan)
                .padding(.bottom, 3)
            
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

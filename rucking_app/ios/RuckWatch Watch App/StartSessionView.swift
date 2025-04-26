//
//  StartSessionView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

struct StartSessionView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var ruckWeight: Double = 10.0 // Default weight
    
    // Weight options to display as tiles
    private let weightOptions: [Double] = [5, 10, 15, 20, 25, 30, 35, 40]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Title at the top, left-aligned with zero top spacing
                Text("GRY")
                    .font(.system(size: 24))
                    .bold()
                    .padding(.top, 2) // Small positive padding instead of negative
                
                Text("Ruck Weight: \(Int(ruckWeight)) kg")
                    .font(.system(size: 16))
                    .padding(.bottom, 2)
                
                // Weight selection tiles in a grid layout
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 6) {
                    ForEach(weightOptions, id: \.self) { weight in
                        Button(action: {
                            ruckWeight = weight
                        }) {
                            Text("\(Int(weight))")
                                .font(.system(size: 14, weight: .medium))
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(weight == ruckWeight ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 2)
                
                // Start button
                Button(action: {
                    sessionManager.startSession(withWeight: ruckWeight)
                }) {
                    Text("Start Ruck")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
                .padding(.bottom)
            }
            .padding(.horizontal)
            .padding(.top, 0)
        }
        .edgesIgnoringSafeArea(.top) // Extend content to the very top of the screen
    }
}

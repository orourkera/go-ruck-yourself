//
//  StartSessionView.swift
//  RuckWatch Watch App
//
//  Created by Rory on 25/4/25.
//

import SwiftUI

@available(watchOS 9.0, *)
struct StartSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var ruckWeight: Double = 9.0 // Default weight
    
    // Weight options to display as tiles
    private let weightOptions: [Double] = [2.5, 4.5, 9, 20, 30]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Title at the top, left-aligned with zero top spacing
                Text("GRY")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color("ArmyGreen"))
                    .padding(.top, 2)
                
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
                        Button {
                            ruckWeight = weight
                        } label: {
                            Text("\(Int(weight))")
                                .font(.system(size: 14, weight: .medium))
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(weight == ruckWeight ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 2)
                
                // Start button
                Button {
                    sessionManager.startSession(withWeight: ruckWeight)
                } label: {
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
        .ignoresSafeArea(edges: .top) // Modern syntax for ignoring safe area
    }
}

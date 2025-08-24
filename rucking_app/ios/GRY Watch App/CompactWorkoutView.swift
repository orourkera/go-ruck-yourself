#if os(watchOS)
//  CompactWorkoutView.swift
//  GRY Watch App
//  Displays a single-column, left-aligned workout dashboard that mirrors the Apple Watch system Workout app layout.
//
//  Automatically picks up live metrics from the shared SessionManager singleton.
//
//  Created automatically by Cascade on 18-Jul-2025.

import SwiftUI

struct CompactWorkoutView: View {
    @ObservedObject private var sessionManager = SessionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Activity type icon at the top
                HStack {
                    Image(systemName: "backpack")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.bottom, 0)
                
                // Elapsed time – large and yellow
                Text(sessionManager.statusText)
                    .foregroundColor(.yellow)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .monospacedDigit()

                // Distance (unit embedded in value like elevation)
                metricRow(value: sessionManager.distance, labelLines: [" ", " "]) // Unit embedded in value
                
                // Active calories
                metricRow(value: sessionManager.caloriesText, labelLines: ["ACTIVE", "CAL"])

                // Heart-rate row with heart glyph
                metricRow(value: sessionManager.heartRateText,
                          symbol: AnyView(Image(systemName: "heart.fill").foregroundColor(.red)),
                          labelLines: [" ", " "]) // No label text – glyph suffices

                // Pace with label, but value without unit
                metricRow(value: sessionManager.pace, labelLines: ["AVERAGE", "PACE"])

                // Elevation gain (already formatted with unit)
                metricRow(value: sessionManager.elevationText, labelLines: [" ", " "]) // Unit embedded in value

                Spacer()

                // Controls: Pause/Resume and End buttons side-by-side, icon-only
                HStack(spacing: 8) {
                    // Play/Pause icon button
                    Button(action: {
                        sessionManager.togglePauseResume()
                    }) {
                        Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(sessionManager.isPaused ? .green : .orange)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(sessionManager.isPaused ? "Resume" : "Pause")

                    // Stop icon button
                    Button(action: {
                        sessionManager.endSession()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("End")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 4)
        }
    }

    // Helper that builds a two-line metric row
    private func metricRow(value: String,
                           symbol: AnyView? = nil,
                           labelLines: [String]) -> some View {
        HStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .regular, design: .default))
                .foregroundColor(.white)
                .monospacedDigit()

            if let symbol = symbol {
                symbol
            }

            // Build label (single line if only one element)
            if labelLines.count == 1 && !labelLines[0].isEmpty && labelLines[0] != " " {
                Text(labelLines[0])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            } else if labelLines.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    if labelLines.indices.contains(0) {
                        Text(labelLines[0])
                    }
                    if labelLines.indices.contains(1) {
                        Text(labelLines[1])
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            }
        }
    }
}

struct CompactWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        CompactWorkoutView()
            .previewDevice("Apple Watch Series 9 (45mm)")
    }
}
#endif

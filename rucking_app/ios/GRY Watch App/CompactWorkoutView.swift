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
        ZStack(alignment: .topLeading) {
            // Main metric stack
            VStack(alignment: .leading, spacing: 4) {
                // Elapsed time – large and yellow
                Text(sessionManager.statusText)
                    .foregroundColor(.yellow)
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                    .monospacedDigit()

                // Active calories
                metricRow(value: sessionManager.caloriesText, labelLines: ["ACTIVE", "CAL"])

                // Heart-rate row with heart glyph
                metricRow(value: sessionManager.heartRateText,
                          symbol: AnyView(Image(systemName: "heart.fill").foregroundColor(.red)),
                          labelLines: [" ", " "]) // No label text – glyph suffices

                // Average pace
                metricRow(value: sessionManager.pace, labelLines: ["AVERAGE", "PACE"])

                // Elevation gain (already formatted with unit)
                metricRow(value: sessionManager.elevationText, labelLines: [" ", " "]) // Unit embedded in value

                Spacer()
            }
            .padding(.top, 38) // leave space for the icon row
            .padding(.horizontal, 8)

            // Activity type icon – green walk figure
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
                .padding(.leading, 4)
        }
        // Clock overlay in the native top-right location
        .overlay(
            Text(Date(), style: .time)
                .font(.footnote)
                .foregroundColor(.white)
                .padding([.top, .trailing], 6),
            alignment: .topTrailing
        )
    }

    // Helper that builds a two-line metric row
    private func metricRow(value: String,
                           symbol: AnyView? = nil,
                           labelLines: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .regular, design: .default))
                .foregroundColor(.white)
                .monospacedDigit()

            if let symbol = symbol {
                symbol
            }

            // Build stacked label
            VStack(alignment: .leading, spacing: 0) {
                if labelLines.indices.contains(0) {
                    Text(labelLines[0])
                }
                if labelLines.indices.contains(1) {
                    Text(labelLines[1])
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
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

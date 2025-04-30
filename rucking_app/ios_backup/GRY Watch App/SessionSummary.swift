//
//  SessionSummary.swift
//  RuckWatch Watch App
//
//  Created on 26/4/25.
//

import Foundation

@available(watchOS 9.0, *)
struct SessionSummary {
    let duration: TimeInterval
    let distance: Double  // In meters
    let calories: Double
    let avgHeartRate: Double
    let ruckWeight: Double // In kg
    let elevationGain: Double // In meters
    
    // Add any other metrics you want to include in the review
}

//
//  RideSummaryView.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Read-only summary of one ride, reused by the post-ride sheet and the history
//  detail screen.
//

import SwiftUI
import IndoorRideCore

/// Displays the totals of a single ride.
struct RideSummaryView: View {
    let summary: RideSummary

    var body: some View {
        List {
            Section {
                row("Duration", RideSummaryView.duration(summary.activeDuration))
                row("Distance", String(format: "%.2f km", summary.distanceMeters / 1000))
                row("Calories", String(format: "%.0f kcal", summary.energyKilocalories))
            }
            Section("Power") {
                row("Average", "\(Int(summary.averagePower.rounded())) W")
                row("Max", "\(summary.maxPower) W")
            }
            Section("Cadence") {
                row("Average", "\(Int(summary.averageCadence.rounded())) rpm")
                row("Max", "\(Int(summary.maxCadence.rounded())) rpm")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).font(.body.monospacedDigit())
        }
    }

    /// Format seconds as h:mm:ss or m:ss.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

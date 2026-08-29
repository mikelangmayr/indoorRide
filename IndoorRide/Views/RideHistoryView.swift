//
//  RideHistoryView.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  List of finished rides, newest first, with a detail summary and swipe delete.
//

import SwiftUI
import IndoorRideCore

/// Browses saved rides.
struct RideHistoryView: View {
    let history: RideHistory

    var body: some View {
        List {
            ForEach(history.rides) { ride in
                NavigationLink {
                    RideSummaryView(summary: ride.summary)
                        .navigationTitle(Self.title(for: ride.summary.startDate))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    row(for: ride)
                }
            }
            .onDelete { offsets in
                offsets.map { history.rides[$0] }.forEach(history.delete)
            }
        }
        .navigationTitle("History")
        .overlay {
            if history.rides.isEmpty {
                ContentUnavailableView(
                    "No rides yet",
                    systemImage: "bicycle",
                    description: Text("Finished rides you save will appear here.")
                )
            }
        }
    }

    private func row(for ride: CompletedRide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.title(for: ride.summary.startDate))
                .font(.headline)
            HStack(spacing: 12) {
                Label(String(format: "%.1f km", ride.summary.distanceMeters / 1000),
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label(RideSummaryView.duration(ride.summary.activeDuration),
                      systemImage: "clock")
                Label("\(Int(ride.summary.averagePower.rounded())) W",
                      systemImage: "bolt.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    static func title(for date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

#if DEBUG
private final class PreviewHistoryStore: RideHistoryStore {
    private var rides: [CompletedRide]
    init(_ rides: [CompletedRide]) { self.rides = rides }
    func load() -> [CompletedRide] { rides }
    func save(_ rides: [CompletedRide]) { self.rides = rides }
}

#Preview {
    func ride(daysAgo: Int, minutes: Int, watts: Int) -> CompletedRide {
        let start = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        var accumulator = RideAccumulator(startDate: start)
        for second in 1...(minutes * 60) {
            accumulator.integrate(power: watts, cadence: Double(watts) / 2, speedKmh: 30,
                                  at: start.addingTimeInterval(TimeInterval(second)))
        }
        return CompletedRide(summary: RideSummary(from: accumulator))
    }
    let store = PreviewHistoryStore([
        ride(daysAgo: 0, minutes: 32, watts: 190),
        ride(daysAgo: 2, minutes: 45, watts: 165),
        ride(daysAgo: 5, minutes: 20, watts: 210)
    ])
    return NavigationStack { RideHistoryView(history: RideHistory(store: store)) }
}
#endif

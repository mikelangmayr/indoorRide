//
//  RideHistoryTests.swift
//  IndoorRideTests
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  History behavior with an in-memory store: newest-first ordering, reload, and
//  delete, all without touching disk.
//

import Testing
import Foundation
import IndoorRideCore
@testable import IndoorRide

private final class InMemoryHistoryStore: RideHistoryStore {
    var saved: [CompletedRide] = []
    func load() -> [CompletedRide] { saved }
    func save(_ rides: [CompletedRide]) { saved = rides }
}

private func summary(startingAt seconds: TimeInterval) -> RideSummary {
    var accumulator = RideAccumulator(
        startDate: Date(timeIntervalSinceReferenceDate: seconds)
    )
    accumulator.integrate(power: 100, cadence: 60, speedKmh: 30,
                          at: Date(timeIntervalSinceReferenceDate: seconds))
    return RideSummary(from: accumulator)
}

@Suite("Ride history")
struct RideHistoryTests {

    @Test func addInsertsNewestFirstAndPersists() {
        let store = InMemoryHistoryStore()
        let history = RideHistory(store: store)
        history.add(summary(startingAt: 0))
        history.add(summary(startingAt: 100))

        #expect(history.rides.count == 2)
        #expect(history.rides.first?.summary.startDate
                == Date(timeIntervalSinceReferenceDate: 100))
        #expect(store.saved.count == 2)
    }

    @Test func loadsExistingOnInit() {
        let store = InMemoryHistoryStore()
        RideHistory(store: store).add(summary(startingAt: 0))

        let reopened = RideHistory(store: store)
        #expect(reopened.rides.count == 1)
    }

    @Test func deleteRemovesAndPersists() throws {
        let store = InMemoryHistoryStore()
        let history = RideHistory(store: store)
        history.add(summary(startingAt: 0))
        let ride = try #require(history.rides.first)

        history.delete(ride)
        #expect(history.rides.isEmpty)
        #expect(store.saved.isEmpty)
    }
}

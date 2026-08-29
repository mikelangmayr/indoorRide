//
//  LiveMetricsTests.swift
//  IndoorRideTests
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  The live frame travels between devices as JSON-encoded Data, so its Codable
//  round-trip, including absent optionals, is what has to hold.
//

import Testing
import Foundation
import IndoorRideCore

@Suite("Live metrics")
struct LiveMetricsTests {

    @Test func roundTripsThroughJSON() throws {
        let metrics = LiveMetrics(
            state: .recording,
            elapsed: 123,
            power: 150,
            cadence: 82.5,
            speed: 28.4,
            heartRate: 140,
            energyKilocalories: 45.6,
            distanceMeters: 5200
        )
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(LiveMetrics.self, from: data)
        #expect(decoded == metrics)
    }

    @Test func absentOptionalsSurviveRoundTrip() throws {
        let metrics = LiveMetrics(
            state: .paused,
            elapsed: 0,
            power: nil,
            cadence: nil,
            speed: nil,
            heartRate: nil,
            energyKilocalories: 0,
            distanceMeters: 0
        )
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(LiveMetrics.self, from: data)
        #expect(decoded == metrics)
        #expect(decoded.power == nil)
    }
}

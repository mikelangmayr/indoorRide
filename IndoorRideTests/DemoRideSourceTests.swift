//
//  DemoRideSourceTests.swift
//  IndoorRideTests
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  The demo source is only honest if its packets decode through the same parser
//  the live connection uses. This round-trips one packet to prove it.
//

import Testing
import Foundation
import IndoorRideCore
@testable import IndoorRide

@Suite("Demo ride source")
struct DemoRideSourceTests {

    @Test func packetRoundTripsThroughRealParser() throws {
        let data = indoorBikeDataPacket(
            speedKmh: 25.0,
            cadenceRpm: 80,
            powerW: 150,
            heartRate: 130
        )
        let sample = try #require(IndoorBikeData(data))
        #expect(sample.instantaneousSpeed == 25.0)
        #expect(sample.instantaneousCadence == 80.0)
        #expect(sample.instantaneousPower == 150)
        #expect(sample.heartRate == 130)
    }
}

//
//  IndoorBikeDataTests.swift
//  IndoorRideTests
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Test vectors captured from a Schwinn IC4 ("IC Bike") on 2026-08-27 with
//  nRF Connect. These are real bytes off real hardware, not synthesised,
//  which is what makes them worth keeping.
//

import Testing
import Foundation
import IndoorRideCore
@testable import IndoorRide

private func hex(_ string: String) -> Data {
    let cleaned = string.replacingOccurrences(of: " ", with: "")
    var bytes = [UInt8]()
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
        let next = cleaned.index(index, offsetBy: 2)
        bytes.append(UInt8(cleaned[index..<next], radix: 16)!)
        index = next
    }
    return Data(bytes)
}

@Suite("Indoor Bike Data")
struct IndoorBikeDataTests {

    /// Captured ~22 s into a ride, pedalling gently.
    @Test func decodesFirstCapture() throws {
        let data = hex("740B 8606 3000 5800 001A 0020 0001 0000 0000 0016 00")
        let sample = try #require(IndoorBikeData(data))

        #expect(sample.instantaneousSpeed == 16.70)
        #expect(sample.instantaneousCadence == 24.0)
        #expect(sample.totalDistance == 88)
        #expect(sample.resistanceLevelRaw == 26)
        #expect(sample.instantaneousPower == 32)
        #expect(sample.totalEnergy == 1)
        #expect(sample.heartRate == 0)
        #expect(sample.elapsedTime == 22)
    }

    /// Captured 60 s later. 411 - 88 = 323 m in 60 s ≈ 19.4 km/h, which sits
    /// between the two instantaneous speed readings: the cross-check that
    /// proves the field offsets are right rather than merely plausible.
    @Test func decodesSecondCapture() throws {
        let data = hex("740B 4808 3E00 9B01 0025 0037 0005 0000 0000 0052 00")
        let sample = try #require(IndoorBikeData(data))

        #expect(sample.instantaneousSpeed == 21.20)
        #expect(sample.instantaneousCadence == 31.0)
        #expect(sample.totalDistance == 411)
        #expect(sample.resistanceLevelRaw == 37)
        #expect(sample.instantaneousPower == 55)
        #expect(sample.totalEnergy == 5)
        #expect(sample.elapsedTime == 82)
    }

    /// The 24-bit Total Distance field is the one that breaks naive parsers:
    /// read it as 16 or 32 bits and every field after it silently shifts.
    @Test func totalDistanceIsTwentyFourBit() throws {
        let data = hex("740B 4808 3E00 9B01 0025 0037 0005 0000 0000 0052 00")
        let sample = try #require(IndoorBikeData(data))
        #expect(sample.totalDistance == 0x00019B)
        // If distance were mis-sized, power would land on the wrong bytes.
        #expect(sample.instantaneousPower == 55)
    }

    /// A truncated packet must degrade to nils, not trap. Peripherals send
    /// short and malformed payloads more often than the spec suggests.
    @Test func truncatedPacketDoesNotCrash() throws {
        let data = hex("740B 8606 30")
        let sample = try #require(IndoorBikeData(data))
        #expect(sample.instantaneousSpeed == 16.70)
        #expect(sample.instantaneousCadence == nil)
        #expect(sample.instantaneousPower == nil)
    }

    @Test func emptyPayloadReturnsNil() {
        #expect(IndoorBikeData(Data()) == nil)
    }
}

@Suite("Fitness Machine capabilities")
struct FitnessMachineCapabilitiesTests {

    /// The IC4's advertised feature set.
    @Test func decodesIC4Features() throws {
        let capabilities = try #require(
            FitnessMachineCapabilities(hex("8652 0000 0000 0000"))
        )
        #expect(capabilities.features.contains(.cadence))
        #expect(capabilities.features.contains(.totalDistance))
        #expect(capabilities.features.contains(.resistanceLevel))
        #expect(capabilities.features.contains(.expendedEnergy))
        #expect(capabilities.features.contains(.elapsedTime))
        #expect(capabilities.features.contains(.powerMeasurement))

        #expect(!capabilities.features.contains(.inclination))
        // Nothing is settable: the Control Point at 0x2AD9 is advertised but
        // inert. No resistance control, no ERG mode.
        #expect(capabilities.targetSettings == 0)
    }

    @Test func decodesResistanceRange() throws {
        let range = try #require(
            SupportedResistanceLevelRange(hex("0A00 0401 0A00"))
        )
        #expect(range.minimumRaw == 10)
        #expect(range.maximumRaw == 260)
        #expect(range.incrementRaw == 10)
        // Note: these do not agree with the levels the bike actually emits
        // (26, 37, …). Documented, not asserted as meaningful.
    }
}

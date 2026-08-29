//
//  IndoorBikeData.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Parser for the Bluetooth SIG Fitness Machine Service (0x1826):
//    - Indoor Bike Data            (0x2AD2, notify)
//    - Fitness Machine Feature     (0x2ACC, read)
//    - Supported Resistance Range  (0x2AD6, read)
//
//  Verified against a Schwinn IC4 ("IC Bike"), captured 2026-08-27:
//
//    2ACC  8652 0000 0000 0000
//          → cadence, totalDistance, resistanceLevel, expendedEnergy,
//            elapsedTime, powerMeasurement.  Target settings: none.
//
//    2AD2  740B 8606 3000 5800 001A 0020 0001 0000 0000 0016 00
//          → 16.70 km/h · 24.0 rpm · 88 m · resistance 26 · 32 W
//            · 1 kcal · 0 bpm · 22 s
//
//    2AD2  740B 4808 3E00 9B01 0025 0037 0005 0000 0000 0052 00
//          → 21.20 km/h · 31.0 rpm · 411 m · resistance 37 · 55 W
//            · 5 kcal · 0 bpm · 82 s
//
//  Both packets are 21 bytes and consistent with each other: 323 m covered
//  in the 60 s between them ≈ 19.4 km/h, which sits between the two
//  instantaneous speed readings.
//

import Foundation

// MARK: - Byte reader

/// Little-endian cursor over a BLE characteristic payload.
///
/// Every read is bounds-checked. A truncated or malformed packet yields `nil`
/// for the remaining fields rather than trapping: BLE peripherals lie about
/// their own payloads more often than you would hope.
private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    private var remaining: Int { bytes.count - offset }

    mutating func uint8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func int16() -> Int16? {
        guard let raw = uint16() else { return nil }
        return Int16(bitPattern: raw)
    }

    /// 24-bit unsigned, little-endian. Used only by Total Distance, and it is
    /// the field that catches everyone, because 24-bit integers appear nowhere
    /// else in the profile.
    mutating func uint24() -> UInt32? {
        guard remaining >= 3 else { return nil }
        defer { offset += 3 }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
    }
}

// MARK: - Indoor Bike Data flags

/// Flags field of an Indoor Bike Data notification (first two bytes).
public struct IndoorBikeDataFlags: OptionSet, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    /// Inverted relative to every other flag: when this bit is *set*,
    /// Instantaneous Speed is **absent**. Use ``hasInstantaneousSpeed``.
    public static let moreData             = Self(rawValue: 1 << 0)
    public static let averageSpeed         = Self(rawValue: 1 << 1)
    public static let instantaneousCadence = Self(rawValue: 1 << 2)
    public static let averageCadence       = Self(rawValue: 1 << 3)
    public static let totalDistance        = Self(rawValue: 1 << 4)
    public static let resistanceLevel      = Self(rawValue: 1 << 5)
    public static let instantaneousPower   = Self(rawValue: 1 << 6)
    public static let averagePower         = Self(rawValue: 1 << 7)
    public static let expendedEnergy       = Self(rawValue: 1 << 8)
    public static let heartRate            = Self(rawValue: 1 << 9)
    public static let metabolicEquivalent  = Self(rawValue: 1 << 10)
    public static let elapsedTime          = Self(rawValue: 1 << 11)
    public static let remainingTime        = Self(rawValue: 1 << 12)

    public var hasInstantaneousSpeed: Bool { !contains(.moreData) }
}

// MARK: - Indoor Bike Data

/// One decoded Indoor Bike Data notification (characteristic 0x2AD2).
///
/// Every field is optional because the peripheral chooses per-packet which
/// fields to include. On the IC4 the flags are constant at `0x0B74`, but do
/// not rely on that: other machines vary the flags between notifications,
/// and so may a future firmware.
public struct IndoorBikeData: Equatable, Sendable {

    public var flags: IndoorBikeDataFlags

    /// km/h.
    public var instantaneousSpeed: Double?
    /// km/h.
    public var averageSpeed: Double?

    /// Revolutions per minute.
    public var instantaneousCadence: Double?
    /// Revolutions per minute.
    public var averageCadence: Double?

    /// Metres since the session began.
    public var totalDistance: UInt32?

    /// Raw resistance level, exactly as the machine reported it.
    ///
    /// Deliberately unscaled. The FTMS spec nominally applies a 0.1 resolution
    /// here, but the IC4's own Supported Resistance Level Range (0x2AD6)
    /// declares min 10, max 260, increment 10, which is inconsistent with the
    /// values it actually emits (26, 37, …). Map this to the console's 1–100
    /// display empirically before showing it to a rider.
    public var resistanceLevelRaw: Int16?

    /// Watts.
    public var instantaneousPower: Int16?
    /// Watts.
    public var averagePower: Int16?

    /// Kilocalories, as calculated by the machine.
    ///
    /// The IC4 runs roughly 50% above the value you get from integrating its
    /// own reported power, so prefer computing energy yourself:
    /// `kJ = Σ(watts × seconds) / 1000`, and `kcal ≈ kJ`.
    public var totalEnergy: UInt16?
    /// Kilocalories per hour.
    public var energyPerHour: UInt16?
    /// Kilocalories per minute.
    public var energyPerMinute: UInt8?

    /// Beats per minute, relayed from a strap paired to the bike's console.
    /// Zero when no strap is paired. Never write this to HealthKit: the Watch
    /// owns heart rate.
    public var heartRate: UInt8?

    /// Metabolic equivalent of task.
    public var metabolicEquivalent: Double?

    /// Seconds since the session began.
    public var elapsedTime: UInt16?
    /// Seconds remaining in a machine-programmed session.
    public var remainingTime: UInt16?

    /// Parses one notification payload. Returns `nil` only if the packet is too
    /// short to contain a flags field.
    public init?(_ data: Data) {
        var reader = ByteReader(data)
        guard let rawFlags = reader.uint16() else { return nil }
        let flags = IndoorBikeDataFlags(rawValue: rawFlags)
        self.flags = flags

        // Field order is fixed by the spec. Each field is present only if its
        // flag is set, so the cursor must advance in exactly this sequence.

        if flags.hasInstantaneousSpeed {
            instantaneousSpeed = reader.uint16().map { Double($0) * 0.01 }
        }
        if flags.contains(.averageSpeed) {
            averageSpeed = reader.uint16().map { Double($0) * 0.01 }
        }
        if flags.contains(.instantaneousCadence) {
            instantaneousCadence = reader.uint16().map { Double($0) * 0.5 }
        }
        if flags.contains(.averageCadence) {
            averageCadence = reader.uint16().map { Double($0) * 0.5 }
        }
        if flags.contains(.totalDistance) {
            totalDistance = reader.uint24()
        }
        if flags.contains(.resistanceLevel) {
            resistanceLevelRaw = reader.int16()
        }
        if flags.contains(.instantaneousPower) {
            instantaneousPower = reader.int16()
        }
        if flags.contains(.averagePower) {
            averagePower = reader.int16()
        }
        if flags.contains(.expendedEnergy) {
            totalEnergy     = reader.uint16()
            energyPerHour   = reader.uint16()
            energyPerMinute = reader.uint8()
        }
        if flags.contains(.heartRate) {
            heartRate = reader.uint8()
        }
        if flags.contains(.metabolicEquivalent) {
            metabolicEquivalent = reader.uint8().map { Double($0) * 0.1 }
        }
        if flags.contains(.elapsedTime) {
            elapsedTime = reader.uint16()
        }
        if flags.contains(.remainingTime) {
            remainingTime = reader.uint16()
        }
    }
}

// MARK: - Fitness Machine Feature

/// Fitness Machine Feature bitfield (characteristic 0x2ACC, first 4 bytes).
///
/// Read this once on connect to learn what the machine can report, rather than
/// hardcoding assumptions about a particular bike.
public struct FitnessMachineFeature: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let averageSpeed        = Self(rawValue: 1 << 0)
    public static let cadence             = Self(rawValue: 1 << 1)
    public static let totalDistance       = Self(rawValue: 1 << 2)
    public static let inclination         = Self(rawValue: 1 << 3)
    public static let elevationGain       = Self(rawValue: 1 << 4)
    public static let pace                = Self(rawValue: 1 << 5)
    public static let stepCount           = Self(rawValue: 1 << 6)
    public static let resistanceLevel     = Self(rawValue: 1 << 7)
    public static let strideCount         = Self(rawValue: 1 << 8)
    public static let expendedEnergy      = Self(rawValue: 1 << 9)
    public static let heartRateMeasurement = Self(rawValue: 1 << 10)
    public static let metabolicEquivalent = Self(rawValue: 1 << 11)
    public static let elapsedTime         = Self(rawValue: 1 << 12)
    public static let remainingTime       = Self(rawValue: 1 << 13)
    public static let powerMeasurement    = Self(rawValue: 1 << 14)
    public static let forceOnBeltAndPower = Self(rawValue: 1 << 15)
    public static let userDataRetention   = Self(rawValue: 1 << 16)
}

/// Both halves of the Fitness Machine Feature characteristic.
public struct FitnessMachineCapabilities: Equatable, Sendable {
    public let features: FitnessMachineFeature
    /// Bitfield of settings the Control Point will accept.
    /// **Zero on the IC4**: its Control Point (0x2AD9) is advertised but inert,
    /// so there is no resistance control and no ERG mode.
    public let targetSettings: UInt32

    public init?(_ data: Data) {
        var reader = ByteReader(data)
        guard let low = reader.uint16(), let high = reader.uint16(),
              let targetLow = reader.uint16(), let targetHigh = reader.uint16()
        else { return nil }
        features = FitnessMachineFeature(
            rawValue: UInt32(low) | UInt32(high) << 16
        )
        targetSettings = UInt32(targetLow) | UInt32(targetHigh) << 16
    }
}

// MARK: - Supported Resistance Level Range

/// Supported Resistance Level Range (characteristic 0x2AD6).
///
/// Values are raw. See the note on ``IndoorBikeData/resistanceLevelRaw``: the
/// IC4's declared range does not agree with the levels it actually emits, so
/// treat this as a hint rather than a contract.
public struct SupportedResistanceLevelRange: Equatable, Sendable {
    public let minimumRaw: Int16
    public let maximumRaw: Int16
    public let incrementRaw: UInt16

    public init?(_ data: Data) {
        var reader = ByteReader(data)
        guard let minimum = reader.int16(),
              let maximum = reader.int16(),
              let increment = reader.uint16()
        else { return nil }
        minimumRaw = minimum
        maximumRaw = maximum
        incrementRaw = increment
    }
}

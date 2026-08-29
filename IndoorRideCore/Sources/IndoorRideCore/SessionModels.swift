//
//  SessionModels.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Value types for a recorded ride: the per-second sample, the running
//  accumulator that turns 1 Hz samples into totals, and the summary the UI and
//  HealthKit consume. All are Codable so an in-progress ride survives a crash.
//

import Foundation

/// Lifecycle of a recording session.
public enum RideSessionState: String, Codable, Sendable {
    case idle
    case recording
    case paused
    case finished
}

/// One 1 Hz snapshot of the ride, kept for the time-series HealthKit and Strava
/// will later want. Every field is optional because a packet may omit it.
public struct RideSample: Equatable, Sendable, Codable {
    public var timestamp: Date
    /// Watts.
    public var power: Int?
    /// Revolutions per minute.
    public var cadence: Double?
    /// km/h.
    public var speed: Double?
    /// Beats per minute, or nil when no strap is paired to the console.
    public var heartRate: Int?

    public init(
        timestamp: Date,
        power: Int?,
        cadence: Double?,
        speed: Double?,
        heartRate: Int?
    ) {
        self.timestamp = timestamp
        self.power = power
        self.cadence = cadence
        self.speed = speed
        self.heartRate = heartRate
    }
}

/// Running totals for a ride, integrated over real elapsed time between samples.
///
/// Averages are time-weighted rather than a plain mean of samples: a sample that
/// represents three seconds of pedalling counts three times as much as one that
/// represents a single second. Only time spent actually pedalling accrues, so a
/// mid-ride pause never dilutes the averages.
public struct RideAccumulator: Equatable, Sendable, Codable {

    /// Longest gap between two samples we still treat as continuous pedalling.
    /// A hiccup in the BLE stream must not integrate a huge slug of energy.
    public static let defaultMaxSampleGap: TimeInterval = 3

    public var startDate: Date
    public private(set) var activeSeconds: TimeInterval = 0
    public private(set) var distanceMeters: Double = 0

    /// Σ(watts × seconds). Energy in kJ is this over 1000; average power is this
    /// over `activeSeconds`. Both derive from the one integral.
    public private(set) var powerJoules: Double = 0
    /// Σ(rpm × seconds), for the time-weighted cadence average.
    public private(set) var cadenceRevSeconds: Double = 0

    public private(set) var maxPower: Int = 0
    public private(set) var maxCadence: Double = 0
    public private(set) var sampleCount: Int = 0

    /// Timestamp of the last integrated moving sample. Nil across a pause so the
    /// next interval starts fresh instead of spanning the idle gap.
    public var lastMovingDate: Date?

    public init(startDate: Date) {
        self.startDate = startDate
    }

    /// Fold one moving sample into the totals. Missing power/cadence/speed are
    /// treated as zero; negative power contributes nothing to energy.
    public mutating func integrate(
        power: Int,
        cadence: Double,
        speedKmh: Double,
        at date: Date,
        maxGap: TimeInterval = RideAccumulator.defaultMaxSampleGap
    ) {
        maxPower = max(maxPower, power)
        maxCadence = max(maxCadence, cadence)
        sampleCount += 1

        defer { lastMovingDate = date }
        guard let last = lastMovingDate else { return }
        let dt = min(date.timeIntervalSince(last), maxGap)
        guard dt > 0 else { return }

        activeSeconds += dt
        powerJoules += Double(max(0, power)) * dt
        cadenceRevSeconds += cadence * dt
        distanceMeters += speedKmh * (1000.0 / 3600.0) * dt
    }
}

/// Immutable snapshot of a ride's totals, derived from a ``RideAccumulator``.
public struct RideSummary: Equatable, Sendable, Codable {
    public var startDate: Date
    public var activeDuration: TimeInterval
    public var distanceMeters: Double
    public var energyKilocalories: Double
    /// Time-weighted mean watts over active time.
    public var averagePower: Double
    public var maxPower: Int
    /// Time-weighted mean rpm over active time.
    public var averageCadence: Double
    public var maxCadence: Double
    public var sampleCount: Int

    public init(from accumulator: RideAccumulator) {
        startDate = accumulator.startDate
        activeDuration = accumulator.activeSeconds
        distanceMeters = accumulator.distanceMeters
        // The 0.239 kcal/kJ conversion and ~24% human efficiency nearly cancel,
        // so mechanical kJ is a good proxy for dietary kcal. See ic4-app-plan.
        energyKilocalories = accumulator.powerJoules / 1000
        let seconds = accumulator.activeSeconds
        averagePower = seconds > 0 ? accumulator.powerJoules / seconds : 0
        averageCadence = seconds > 0 ? accumulator.cadenceRevSeconds / seconds : 0
        maxPower = accumulator.maxPower
        maxCadence = accumulator.maxCadence
        sampleCount = accumulator.sampleCount
    }
}

/// Everything needed to resume an interrupted ride after a crash or relaunch.
public struct RideSnapshot: Equatable, Sendable, Codable {
    public var state: RideSessionState
    public var userPaused: Bool
    public var accumulator: RideAccumulator
    public var samples: [RideSample]

    public init(
        state: RideSessionState,
        userPaused: Bool,
        accumulator: RideAccumulator,
        samples: [RideSample]
    ) {
        self.state = state
        self.userPaused = userPaused
        self.accumulator = accumulator
        self.samples = samples
    }
}

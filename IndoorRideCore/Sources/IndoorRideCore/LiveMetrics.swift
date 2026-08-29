//
//  LiveMetrics.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  The snapshot the phone streams to the watch at 1 Hz. Pure Codable so it can
//  travel over WatchConnectivity as encoded Data with no platform coupling.
//

import Foundation

/// One frame of live ride state sent phone to watch.
public struct LiveMetrics: Codable, Sendable, Equatable {
    public var state: RideSessionState
    /// Active ride time in seconds.
    public var elapsed: TimeInterval
    /// Watts.
    public var power: Int?
    /// Revolutions per minute.
    public var cadence: Double?
    /// km/h.
    public var speed: Double?
    /// Beats per minute, or nil when no strap is paired to the console.
    public var heartRate: Int?
    public var energyKilocalories: Double
    public var distanceMeters: Double

    public init(
        state: RideSessionState,
        elapsed: TimeInterval,
        power: Int?,
        cadence: Double?,
        speed: Double?,
        heartRate: Int?,
        energyKilocalories: Double,
        distanceMeters: Double
    ) {
        self.state = state
        self.elapsed = elapsed
        self.power = power
        self.cadence = cadence
        self.speed = speed
        self.heartRate = heartRate
        self.energyKilocalories = energyKilocalories
        self.distanceMeters = distanceMeters
    }
}

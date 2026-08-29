//
//  DemoRideSource.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Synthetic bike for development and App Review, which has no IC4 to exercise.
//  It builds real Indoor Bike Data (0x2AD2) byte packets and decodes them
//  through the same `IndoorBikeData` parser the live connection uses, so the
//  whole recording pipeline runs unchanged: only the bytes' origin differs.
//

import Foundation
import IndoorRideCore
import Observation

/// Encode a synthetic Indoor Bike Data packet with speed, cadence, power, and
/// heart rate present. Exposed (not private) so a test can round-trip it through
/// the real parser.
func indoorBikeDataPacket(
    speedKmh: Double,
    cadenceRpm: Double,
    powerW: Int,
    heartRate: Int
) -> Data {
    // Flags: instantaneous cadence (bit 2), power (bit 6), heart rate (bit 9).
    // Bit 0 clear means instantaneous speed is present.
    let flags: UInt16 = (1 << 2) | (1 << 6) | (1 << 9)
    let speed = UInt16(clamping: Int((speedKmh / 0.01).rounded()))
    let cadence = UInt16(clamping: Int((cadenceRpm / 0.5).rounded()))
    let power = UInt16(bitPattern: Int16(clamping: powerW))

    var bytes: [UInt8] = []
    func appendLittleEndian(_ value: UInt16) {
        bytes.append(UInt8(value & 0xff))
        bytes.append(UInt8(value >> 8))
    }
    appendLittleEndian(flags)
    appendLittleEndian(speed)
    appendLittleEndian(cadence)
    appendLittleEndian(power)
    bytes.append(UInt8(clamping: heartRate))
    return Data(bytes)
}

/// A `BikeDataSource` that replays a believable ride at 1 Hz.
@Observable
@MainActor
final class DemoRideSource: BikeDataSource {

    private(set) var state: BikeConnectionState = .searching
    private(set) var latest: IndoorBikeData?
    private(set) var lastUpdate: Date?

    private var task: Task<Void, Never>?

    /// Begin emitting packets. Idempotent.
    func start() {
        guard task == nil else { return }
        state = .connected
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        state = .searching
    }

    private func run() async {
        var second = 0
        while !Task.isCancelled {
            let point = Self.profile(second: second)
            let packet = indoorBikeDataPacket(
                speedKmh: point.speedKmh,
                cadenceRpm: point.cadenceRpm,
                powerW: point.powerW,
                heartRate: point.heartRate
            )
            latest = IndoorBikeData(packet)
            lastUpdate = Date()
            second += 1
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// A ride profile: a 20 s warmup, then a steady effort with gentle surges.
    /// Cadence stays above zero from the first second so recording never
    /// auto-pauses at the start.
    private static func profile(
        second: Int
    ) -> (speedKmh: Double, cadenceRpm: Double, powerW: Int, heartRate: Int) {
        let time = Double(second)
        let warmup = min(1.0, (time + 1) / 20)
        let surge = sin(time / 12)

        let power = 130 * warmup + 25 * surge
        let cadence = (72 + 10 * sin(time / 10)) * warmup
        let speed = (22 + 6 * surge) * warmup
        let heartRate = 95 + 45 * warmup + 6 * sin(time / 15)

        return (
            speedKmh: max(0, speed),
            cadenceRpm: max(0, cadence),
            powerW: Int(max(0, power)),
            heartRate: Int(heartRate)
        )
    }
}

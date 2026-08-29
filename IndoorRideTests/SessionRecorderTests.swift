//
//  SessionRecorderTests.swift
//  IndoorRideTests
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Exercises the recorder with deterministic timestamps: no wall clock, so the
//  time-weighted totals and the pause logic are checked exactly.
//

import Testing
import Foundation
import IndoorRideCore
@testable import IndoorRide

/// Reference instant the tests build their timeline from.
private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

/// Build a moving Indoor Bike Data packet with speed, cadence, and power set.
private func ride(speedKmh: Double, cadenceRpm: Double, powerW: Int) -> IndoorBikeData {
    let flags: UInt16 = (1 << 2) | (1 << 6) // cadence + power; bit0 clear = speed present
    let speed = UInt16((speedKmh / 0.01).rounded())
    let cadence = UInt16((cadenceRpm / 0.5).rounded())
    let power = UInt16(bitPattern: Int16(powerW))

    var bytes: [UInt8] = []
    func append16(_ value: UInt16) {
        bytes.append(UInt8(value & 0xff))
        bytes.append(UInt8(value >> 8))
    }
    append16(flags)
    append16(speed)
    append16(cadence)
    append16(power)
    return IndoorBikeData(Data(bytes))!
}

/// A stopped-cranks packet: zero cadence, zero power.
private let stopped = ride(speedKmh: 0, cadenceRpm: 0, powerW: 0)

/// In-memory `RideStore` so persistence can be inspected without touching disk.
private final class InMemoryRideStore: RideStore {
    private(set) var snapshot: RideSnapshot?
    func save(_ snapshot: RideSnapshot) { self.snapshot = snapshot }
    func load() -> RideSnapshot? { snapshot }
    func clear() { snapshot = nil }
}

@Suite("Session recorder")
struct SessionRecorderTests {

    @Test func ignoresPacketsBeforeStart() {
        let recorder = SessionRecorder()
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        #expect(recorder.state == .idle)
        #expect(recorder.summary == nil)
    }

    @Test func integratesTimeWeightedTotals() throws {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        for second in 0...2 {
            recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100),
                            at: at(TimeInterval(second)))
        }
        let summary = try #require(recorder.summary)

        #expect(summary.activeDuration == 2) // two 1 s intervals across three samples
        #expect(summary.averagePower == 100)
        #expect(summary.maxPower == 100)
        #expect(summary.averageCadence == 60)
        // 30 km/h = 8.333 m/s over 2 s
        #expect(abs(summary.distanceMeters - 16.667) < 0.01)
    }

    @Test func computesEnergyFromPower() throws {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        for second in 0...10 {
            recorder.record(ride(speedKmh: 25, cadenceRpm: 80, powerW: 200),
                            at: at(TimeInterval(second)))
        }
        let summary = try #require(recorder.summary)
        // 200 W x 10 s = 2000 J = 2 kJ ~= 2 kcal
        #expect(abs(summary.energyKilocalories - 2.0) < 1e-6)
        #expect(summary.averagePower == 200)
    }

    @Test func powerScaleMultipliesRecordedPower() throws {
        let recorder = SessionRecorder()
        recorder.powerScale = 2.0
        recorder.start(at: at(0))
        for second in 0...2 {
            recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100),
                            at: at(TimeInterval(second)))
        }
        let summary = try #require(recorder.summary)
        #expect(summary.averagePower == 200)
        #expect(summary.maxPower == 200)
    }

    @Test func autoPausesWhenCranksStopAndResumesOnMovement() {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.record(stopped, at: at(1))
        #expect(recorder.state == .paused)

        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(2))
        #expect(recorder.state == .recording)
    }

    @Test func manualPauseHoldsThroughMovement() {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.pause(at: at(1))

        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(2))
        #expect(recorder.state == .paused) // still paused: only resume() lifts it

        recorder.resume(at: at(3))
        #expect(recorder.state == .recording)
    }

    @Test func pausedGapDoesNotInflateTotals() throws {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(1))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(2))
        recorder.record(stopped, at: at(3)) // auto-pause for a long idle stretch
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(10))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(11))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(12))

        let summary = try #require(recorder.summary)
        #expect(summary.activeDuration == 4) // 2 s + 2 s, the idle gap excluded
    }

    @Test func gapLongerThanMaxIsCapped() throws {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(100))
        let summary = try #require(recorder.summary)
        #expect(summary.activeDuration == RideAccumulator.defaultMaxSampleGap)
    }

    @Test func checkTimeoutAutoPausesAfterDropout() {
        let recorder = SessionRecorder(autoPauseTimeout: 4)
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.checkTimeout(now: at(3))
        #expect(recorder.state == .recording)
        recorder.checkTimeout(now: at(5))
        #expect(recorder.state == .paused)
    }

    @Test func disconnectPauses() {
        let recorder = SessionRecorder()
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.noteDisconnected(at: at(1))
        #expect(recorder.state == .paused)
    }

    @Test func autoStopsAfterProlongedInactivity() {
        let recorder = SessionRecorder(autoPauseTimeout: 4, autoStopTimeout: 30)
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.checkTimeout(now: at(10)) // past pause, before stop
        #expect(recorder.state == .paused)
        recorder.checkTimeout(now: at(31)) // past stop
        #expect(recorder.state == .finished)
    }

    @Test func autoStopLeavesManualPauseAlone() {
        let recorder = SessionRecorder(autoPauseTimeout: 4, autoStopTimeout: 30)
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.pause(at: at(1))
        recorder.checkTimeout(now: at(100)) // the rider chose to pause; do not end
        #expect(recorder.state == .paused)
    }

    @Test func recoversInProgressRideFromStore() throws {
        let store = InMemoryRideStore()
        let first = SessionRecorder(store: store)
        first.start(at: at(0))
        first.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        first.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(1))

        let recovered = SessionRecorder(store: store)
        #expect(recovered.state == .paused)
        #expect(recovered.samples.count == 2)
        let summary = try #require(recovered.summary)
        #expect(summary.activeDuration == 1)
    }

    @Test func stopClearsStoreAndKeepsSummary() throws {
        let store = InMemoryRideStore()
        let recorder = SessionRecorder(store: store)
        recorder.start(at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(0))
        recorder.record(ride(speedKmh: 30, cadenceRpm: 60, powerW: 100), at: at(1))

        let summary = try #require(recorder.stop(at: at(2)))
        #expect(recorder.state == .finished)
        #expect(summary.activeDuration == 1)
        #expect(store.load() == nil) // crash-recovery snapshot discarded
    }
}

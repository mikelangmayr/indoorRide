//
//  SessionRecorder.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Turns the bike's 1 Hz Indoor Bike Data stream into a recordable ride,
//  independent of any UI. Owns start/pause/resume/stop, running totals, energy
//  computed from power, and auto-pause when the rider stops or the bike drops.
//
//  Time is passed in explicitly on every mutating call. That keeps the recorder
//  deterministic and testable, and lets a caller replay a captured ride through
//  it at full speed.
//

import Foundation
import IndoorRideCore
import Observation

/// Records one indoor cycling session from a stream of decoded bike packets.
@Observable
public final class SessionRecorder {

    // MARK: Published state

    public private(set) var state: RideSessionState = .idle

    /// Time-series kept at roughly 1 Hz for later HealthKit and Strava export.
    public private(set) var samples: [RideSample] = []

    /// Live totals, or nil before the first ride starts.
    public var summary: RideSummary? {
        accumulator.map(RideSummary.init(from:))
    }

    // MARK: Configuration

    /// No new packets for this long while recording means the bike dropped off
    /// the air (its radio sleeps when the cranks stop), so auto-pause.
    private let autoPauseTimeout: TimeInterval
    private let maxSampleGap: TimeInterval

    // MARK: Private

    private let store: RideStore?
    private var accumulator: RideAccumulator?

    /// True only when the rider pressed pause. An auto-pause (cranks stopped or
    /// bike dropped) leaves this false, so movement can auto-resume; a manual
    /// pause stays paused until `resume()` is called.
    private var userPaused = false

    /// Reference-time second of the last appended sample and last persisted
    /// snapshot, so both throttle to at most once per second.
    private var lastSampleSecond: Int?
    private var lastPersistSecond: Int?

    // MARK: Lifecycle

    public init(
        store: RideStore? = nil,
        autoPauseTimeout: TimeInterval = 4,
        maxSampleGap: TimeInterval = RideAccumulator.defaultMaxSampleGap
    ) {
        self.store = store
        self.autoPauseTimeout = autoPauseTimeout
        self.maxSampleGap = maxSampleGap
        restoreInProgressRide()
    }

    private func restoreInProgressRide() {
        guard let snapshot = store?.load(), snapshot.state != .finished else { return }
        accumulator = snapshot.accumulator
        accumulator?.lastMovingDate = nil
        samples = snapshot.samples
        userPaused = snapshot.userPaused
        // Resume paused: we cannot know from disk whether the rider is still on
        // the bike, so wait for movement (or an explicit resume) to continue.
        state = .paused
    }

    // MARK: Commands

    public func start(at date: Date = .now) {
        accumulator = RideAccumulator(startDate: date)
        samples = []
        userPaused = false
        lastSampleSecond = nil
        lastPersistSecond = nil
        state = .recording
        persist()
    }

    public func pause(at date: Date = .now) {
        guard state == .recording else { return }
        userPaused = true
        enterPaused()
        persist()
    }

    public func resume(at date: Date = .now) {
        guard state == .paused else { return }
        userPaused = false
        state = .recording
        persist()
    }

    @discardableResult
    public func stop(at date: Date = .now) -> RideSummary? {
        guard state == .recording || state == .paused else { return summary }
        state = .finished
        // The ride is complete, so the crash-recovery snapshot is no longer
        // needed. Finished-ride history is persisted elsewhere.
        store?.clear()
        return summary
    }

    /// Feed one decoded notification. Ignored unless a ride is active.
    public func record(_ data: IndoorBikeData, at date: Date = .now) {
        let power = data.instantaneousPower.map(Int.init)
        let heartRate = data.heartRate.flatMap { $0 == 0 ? nil : Int($0) }
        ingest(
            power: power,
            cadence: data.instantaneousCadence,
            speedKmh: data.instantaneousSpeed,
            heartRate: heartRate,
            at: date
        )
    }

    /// Auto-pause when the bike has gone quiet for longer than the timeout.
    /// Call periodically (a 1 Hz timer) so a mid-ride dropout is caught even
    /// though, by definition, no further packets arrive to trigger it.
    public func checkTimeout(now: Date = .now) {
        guard state == .recording, let last = accumulator?.lastMovingDate else { return }
        guard now.timeIntervalSince(last) > autoPauseTimeout else { return }
        enterPaused()
        persist()
    }

    /// The BLE connection dropped. Treat as an immediate auto-pause.
    public func noteDisconnected(at date: Date = .now) {
        guard state == .recording else { return }
        enterPaused()
        persist()
    }

    // MARK: Ingestion

    private func ingest(
        power: Int?,
        cadence: Double?,
        speedKmh: Double?,
        heartRate: Int?,
        at date: Date
    ) {
        guard state == .recording || state == .paused else { return }
        let moving = (cadence ?? 0) > 0 || (power ?? 0) > 0

        if state == .paused {
            // A manual pause holds until resume(); an auto-pause lifts on
            // movement.
            guard !userPaused, moving else { return }
            state = .recording
        }

        guard moving else {
            enterPaused()
            return
        }

        accumulator?.integrate(
            power: power ?? 0,
            cadence: cadence ?? 0,
            speedKmh: speedKmh ?? 0,
            at: date,
            maxGap: maxSampleGap
        )
        appendSampleIfDue(
            power: power,
            cadence: cadence,
            speedKmh: speedKmh,
            heartRate: heartRate,
            at: date
        )
        persistIfDue(at: date)
    }

    /// Drop to paused and break the integration interval so idle time is not
    /// counted. Leaves `userPaused` untouched: callers set it as appropriate.
    private func enterPaused() {
        state = .paused
        accumulator?.lastMovingDate = nil
    }

    private func appendSampleIfDue(
        power: Int?,
        cadence: Double?,
        speedKmh: Double?,
        heartRate: Int?,
        at date: Date
    ) {
        let second = Int(date.timeIntervalSinceReferenceDate)
        guard second != lastSampleSecond else { return }
        lastSampleSecond = second
        samples.append(
            RideSample(
                timestamp: date,
                power: power,
                cadence: cadence,
                speed: speedKmh,
                heartRate: heartRate
            )
        )
    }

    // MARK: Persistence

    private func persistIfDue(at date: Date) {
        let second = Int(date.timeIntervalSinceReferenceDate)
        guard second != lastPersistSecond else { return }
        lastPersistSecond = second
        persist()
    }

    private func persist() {
        guard let store, let accumulator else { return }
        store.save(
            RideSnapshot(
                state: state,
                userPaused: userPaused,
                accumulator: accumulator,
                samples: samples
            )
        )
    }
}

//
//  WorkoutManager.swift
//  IndoorRide Watch Watch App
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Owns the watchOS workout session. Its job is continuous heart rate and the
//  live-activity plumbing that keeps the app awake on the wrist; live power and
//  cadence arrive from the phone over WatchConnectivity in a later milestone.
//
//  HealthKit calls the delegate methods on an anonymous serial background queue,
//  so each one reads what it needs there and hops to the main actor to publish.
//

import Foundation
import HealthKit
import Observation

/// Runs an indoor-cycling workout session and publishes its live heart rate and
/// energy for the watch UI to observe.
@Observable
@MainActor
final class WorkoutManager: NSObject {

    /// Where the workout is in its lifecycle.
    enum Phase {
        case idle
        case running
        case paused
        case ended
    }

    private(set) var phase: Phase = .idle
    /// Most recent heart rate in beats per minute, or nil before the first sample.
    private(set) var heartRate: Double?
    /// Active energy in kilocalories, as measured by the Watch.
    private(set) var activeEnergyKilocalories: Double = 0
    /// When the session started, for the elapsed-time display.
    private(set) var startDate: Date?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let heartRateType = HKQuantityType(.heartRate)
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Ask for the read/share types the session needs. Heart rate is read-only;
    /// the Watch owns it and the app never writes it back.
    func requestAuthorization() async {
        guard isHealthDataAvailable else { return }
        let share: Set = [HKQuantityType.workoutType(), activeEnergyType]
        let read: Set<HKObjectType> = [heartRateType, activeEnergyType]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    func start() {
        guard isHealthDataAvailable, session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .indoor

        guard let session = try? HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        ) else { return }

        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder

        let start = Date()
        session.startActivity(with: start)
        builder.beginCollection(withStart: start) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.startDate = start
                self.phase = .running
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func end() {
        guard let session, let builder else { return }
        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.finishWorkout { [weak self] _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.reset()
                }
            }
        }
    }

    private func reset() {
        session = nil
        builder = nil
        heartRate = nil
        startDate = nil
        phase = .ended
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running: phase = .running
            case .paused: phase = .paused
            case .ended: phase = .ended
            default: break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in reset(); phase = .idle }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

            switch quantityType {
            case HKQuantityType(.heartRate):
                let value = statistics.mostRecentQuantity()?.doubleValue(for: beatsPerMinute)
                Task { @MainActor in heartRate = value }
            case HKQuantityType(.activeEnergyBurned):
                let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
                Task { @MainActor in if let value { activeEnergyKilocalories = value } }
            default:
                break
            }
        }
    }
}

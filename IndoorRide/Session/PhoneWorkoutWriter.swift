//
//  PhoneWorkoutWriter.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Writes a finished ride to HealthKit from the phone. Used only when no Apple
//  Watch app is present to own the workout: when a watch is there it writes the
//  workout with live heart rate, and the phone stays out of the way to avoid
//  duplicate workouts and double-counted energy.
//

import Foundation
import HealthKit
import IndoorRideCore

/// Constructs and saves an indoor-cycling workout on iOS from recorded samples.
final class PhoneWorkoutWriter {

    private let healthStore = HKHealthStore()
    private let powerType = HKQuantityType(.cyclingPower)
    private let cadenceType = HKQuantityType(.cyclingCadence)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let cadenceUnit = HKUnit.count().unitDivided(by: .minute())

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Request share access for the types the phone writes. Heart rate is never
    /// written: only a Watch measures it.
    func requestAuthorization() async {
        guard isAvailable else { return }
        let share: Set = [HKQuantityType.workoutType(), energyType, powerType, cadenceType]
        try? await healthStore.requestAuthorization(toShare: share, read: [])
    }

    /// Save one workout built from the ride's samples. Best-effort: a failed
    /// Health write must never disrupt a finished ride.
    func write(summary: RideSummary, samples: [RideSample]) async {
        guard isAvailable, summary.activeDuration > 0 else { return }
        let start = summary.startDate
        let end = samples.last?.timestamp ?? start.addingTimeInterval(summary.activeDuration)
        guard end > start else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        do {
            try await builder.beginCollection(at: start)
            let quantitySamples = quantitySamples(from: samples, energyEnd: end, start: start,
                                                  energy: summary.energyKilocalories)
            if !quantitySamples.isEmpty {
                // `add` has several overloads, so its async form is ambiguous;
                // call the completion API through a continuation instead.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.add(quantitySamples) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {
            // Intentionally swallowed: the ride is already recorded in the app.
        }
    }

    private func quantitySamples(
        from samples: [RideSample],
        energyEnd end: Date,
        start: Date,
        energy: Double
    ) -> [HKSample] {
        var result: [HKSample] = []
        for sample in samples {
            if let power = sample.power, power >= 0 {
                result.append(HKQuantitySample(
                    type: powerType,
                    quantity: HKQuantity(unit: .watt(), doubleValue: Double(power)),
                    start: sample.timestamp, end: sample.timestamp))
            }
            if let cadence = sample.cadence, cadence >= 0 {
                result.append(HKQuantitySample(
                    type: cadenceType,
                    quantity: HKQuantity(unit: cadenceUnit, doubleValue: cadence),
                    start: sample.timestamp, end: sample.timestamp))
            }
        }
        if energy > 0 {
            result.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                start: start, end: end))
        }
        return result
    }
}

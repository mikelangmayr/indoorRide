//
//  ContentView.swift
//  IndoorRide Watch Watch App
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Paged watch UI following Apple's "Build a workout app for Apple Watch":
//  Controls, Metrics, and Now Playing. Power and cadence tiles are placeholders
//  until WatchConnectivity feeds them from the phone.
//

import SwiftUI
import WatchKit
import IndoorRideCore

struct ContentView: View {
    @State private var workout = WorkoutManager()
    @State private var connectivity = RideConnectivity()

    var body: some View {
        TabView {
            ControlsView(workout: workout)
            MetricsView(workout: workout, connectivity: connectivity)
            NowPlayingView()
        }
        .tabViewStyle(.page)
        .task { await workout.requestAuthorization() }
    }
}

// MARK: - Controls

/// Start, pause/resume, and end, sized for a moving wrist: two large buttons
/// rather than four small ones.
private struct ControlsView: View {
    let workout: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            switch workout.phase {
            case .idle, .ended:
                Button(action: workout.start) {
                    Label("Start", systemImage: "play.fill")
                }
                .tint(.green)
            case .running:
                Button(action: workout.pause) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(.yellow)
                Button(action: workout.end) {
                    Label("End", systemImage: "stop.fill")
                }
                .tint(.red)
            case .paused:
                Button(action: workout.resume) {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(.green)
                Button(action: workout.end) {
                    Label("End", systemImage: "stop.fill")
                }
                .tint(.red)
            }
        }
        .buttonStyle(.borderedProminent)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Metrics

/// Live ride metrics. Elapsed time and heart rate come from this device;
/// power and cadence are placeholders until the phone sends them.
private struct MetricsView: View {
    let workout: WorkoutManager
    let connectivity: RideConnectivity

    var body: some View {
        let metrics = connectivity.latestMetrics
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                elapsedText
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)

                metric(
                    value: workout.heartRate.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "BPM",
                    color: .red
                )
                metric(
                    value: String(format: "%.0f", workout.activeEnergyKilocalories),
                    unit: "KCAL",
                    color: .orange
                )
                metric(
                    value: metrics?.power.map { "\($0)" } ?? "—",
                    unit: "W",
                    color: .green
                )
                metric(
                    value: metrics?.cadence.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "RPM",
                    color: .blue
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var elapsedText: some View {
        if let start = workout.startDate, workout.phase == .running {
            Text(start, style: .timer)
        } else {
            Text("0:00")
        }
    }

    private func metric(value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}

//
//  RideView.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  The shipping ride screen: live metrics plus start/pause/stop, recording a
//  session from the phone alone. It observes a `BikeConnection` and forwards
//  each notification into a `SessionRecorder`; the recorder owns all the logic,
//  the view only displays and issues commands.
//

import SwiftUI
import IndoorRideCore

/// Foreground ride screen with live metrics and session controls.
struct RideView: View {
    @State private var bike = BikeConnection()
    @State private var recorder = SessionRecorder(store: FileRideStore.defaultStore())

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                connectionStatus
                metricsGrid
                Spacer()
                controls
            }
            .padding()
            .navigationTitle("IndoorRide")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BikeMonitorView()
                    } label: {
                        Image(systemName: "waveform.and.magnifyingglass")
                    }
                    .accessibilityLabel("Bluetooth diagnostics")
                }
            }
            // Forward every new notification into the recorder. `record` ignores
            // packets until a ride is started, so this is safe to always wire.
            .onChange(of: bike.lastUpdate) {
                guard let latest = bike.latest else { return }
                recorder.record(latest)
            }
            // A dropout is a stop signal independent of cadence going to zero.
            .onChange(of: bike.state) {
                if bike.state != .connected {
                    recorder.noteDisconnected()
                }
            }
            // The bike's radio sleeps when the cranks stop, so no packet arrives
            // to trigger auto-pause. A 1 Hz tick catches that silence.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    recorder.checkTimeout()
                }
            }
        }
    }

    // MARK: - Metrics

    private var metricsGrid: some View {
        let summary = recorder.summary
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            MetricTile(
                title: "Time",
                value: elapsed(summary?.activeDuration ?? 0),
                unit: nil,
                systemImage: "clock"
            )
            MetricTile(
                title: "Power",
                value: bike.latest?.instantaneousPower.map { "\($0)" } ?? "—",
                unit: "W",
                systemImage: "bolt.fill"
            )
            MetricTile(
                title: "Cadence",
                value: bike.latest?.instantaneousCadence
                    .map { String(format: "%.0f", $0) } ?? "—",
                unit: "rpm",
                systemImage: "arrow.triangle.2.circlepath"
            )
            MetricTile(
                title: "Heart rate",
                value: bike.latest?.heartRate
                    .flatMap { $0 == 0 ? nil : "\($0)" } ?? "—",
                unit: "bpm",
                systemImage: "heart.fill"
            )
            MetricTile(
                title: "Calories",
                value: summary.map { String(format: "%.0f", $0.energyKilocalories) } ?? "—",
                unit: "kcal",
                systemImage: "flame.fill"
            )
            MetricTile(
                title: "Distance",
                value: summary.map { String(format: "%.2f", $0.distanceMeters / 1000) } ?? "—",
                unit: "km",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle, .finished:
            Button("Start ride") { recorder.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        case .recording:
            HStack(spacing: 16) {
                Button("Pause") { recorder.pause() }
                    .buttonStyle(.bordered)
                Button("End") { recorder.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        case .paused:
            HStack(spacing: 16) {
                Button("Resume") { recorder.resume() }
                    .buttonStyle(.borderedProminent)
                Button("End") { recorder.stop() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Connection status

    private var connectionStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch bike.state {
        case .unavailable(let reason): reason
        case .searching: "Start pedalling to connect"
        case .connecting: "Connecting…"
        case .connected: bike.latest == nil ? "Connected, waiting for data" : "Connected"
        }
    }

    private var statusColor: Color {
        switch bike.state {
        case .unavailable: .red
        case .searching: .orange
        case .connecting: .yellow
        case .connected: .green
        }
    }

    // MARK: - Formatting

    private func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// One labelled metric with a large monospaced value.
private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    // Monospaced digits stop the numbers jittering at 1 Hz.
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .fontWeight(.semibold)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RideView()
}

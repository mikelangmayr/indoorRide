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
    @State private var source: any BikeDataSource
    @State private var recorder: SessionRecorder
    @State private var connectivity = RideConnectivity()
    @State private var history = RideHistory(store: FileRideHistoryStore.defaultStore())
    @State private var phoneWriter = PhoneWorkoutWriter()
    @State private var finishedSummary: RideSummary?
    @AppStorage(SettingsKey.powerScaleFactor) private var powerScaleFactor = 1.0

    /// Defaults to the live BLE connection with crash-safe persistence. Demo
    /// mode injects a `DemoRideSource` and a store-less recorder so it never
    /// clobbers a real in-progress ride.
    init(
        source: (any BikeDataSource)? = nil,
        recorder: SessionRecorder? = nil
    ) {
        _source = State(initialValue: source ?? BikeConnection())
        _recorder = State(
            initialValue: recorder ?? SessionRecorder(store: FileRideStore.defaultStore())
        )
    }

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
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        RideHistoryView(history: history)
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        // Demo mode replays a synthetic ride through the real
                        // pipeline, so the app is exercisable with no bike.
                        NavigationLink {
                            RideView(source: DemoRideSource(), recorder: SessionRecorder())
                                .navigationTitle("Demo")
                        } label: {
                            Label("Demo mode", systemImage: "play.rectangle.on.rectangle")
                        }
                        NavigationLink {
                            BikeMonitorView()
                        } label: {
                            Label("Bluetooth diagnostics", systemImage: "waveform.and.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Forward every new notification into the recorder. `record` ignores
            // packets until a ride is started, so this is safe to always wire.
            .onChange(of: source.lastUpdate) {
                guard let latest = source.latest else { return }
                recorder.record(latest)
                connectivity.sendLive(currentMetrics())
            }
            // The bike appearing on the air means the rider started pedalling,
            // so auto-start recording; its dropping off is an independent stop
            // signal alongside cadence going to zero.
            .onChange(of: source.state) {
                if source.state == .connected, recorder.state == .idle {
                    recorder.start()
                } else if source.state != .connected {
                    recorder.noteDisconnected()
                }
            }
            // Push every recorder state transition so the watch mirrors
            // start/pause/resume/stop even between 1 Hz packets, and hand over
            // the final summary once the ride ends (button or auto-stop).
            .onChange(of: recorder.state) {
                connectivity.sendLive(currentMetrics())
                if recorder.state == .finished, let summary = recorder.summary {
                    connectivity.sendFinalSummary(summary)
                    finishedSummary = summary
                    writeHealthIfPhoneOwned(summary)
                }
            }
            // The bike's radio sleeps when the cranks stop, so no packet arrives
            // to trigger auto-pause. A 1 Hz tick catches that silence.
            .task {
                recorder.powerScale = powerScaleFactor
                // The watch owns the start button; drive the recorder from the
                // commands it sends.
                connectivity.onCommand = { command in
                    switch command {
                    case .start: recorder.start()
                    case .pause: recorder.pause()
                    case .resume: recorder.resume()
                    case .stop: recorder.stop()
                    }
                }
                (source as? DemoRideSource)?.start()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    recorder.checkTimeout()
                }
            }
            .onChange(of: powerScaleFactor) { recorder.powerScale = powerScaleFactor }
            .onDisappear { (source as? DemoRideSource)?.stop() }
            .sheet(isPresented: Binding(
                get: { finishedSummary != nil },
                set: { if !$0 { finishedSummary = nil } }
            )) {
                if let finishedSummary {
                    postRideSheet(finishedSummary)
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
                value: source.latest?.instantaneousPower.map { "\($0)" } ?? "—",
                unit: "W",
                systemImage: "bolt.fill"
            )
            MetricTile(
                title: "Cadence",
                value: source.latest?.instantaneousCadence
                    .map { String(format: "%.0f", $0) } ?? "—",
                unit: "rpm",
                systemImage: "arrow.triangle.2.circlepath"
            )
            MetricTile(
                title: "Heart rate",
                value: source.latest?.heartRate
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
                Button("End") { endRide() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        case .paused:
            HStack(spacing: 16) {
                Button("Resume") { recorder.resume() }
                    .buttonStyle(.borderedProminent)
                Button("End") { endRide() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    private func endRide() {
        // Stopping flips the recorder to `.finished`, and the state observer
        // sends the final summary to the watch and raises the summary sheet.
        recorder.stop()
    }

    /// Write the workout to HealthKit from the phone only when a watch app is not
    /// there to own it, and never for demo rides.
    private func writeHealthIfPhoneOwned(_ summary: RideSummary) {
        guard !(source is DemoRideSource), !connectivity.isWatchAppInstalled else { return }
        let samples = recorder.samples
        Task {
            await phoneWriter.requestAuthorization()
            await phoneWriter.write(summary: summary, samples: samples)
        }
    }

    private func postRideSheet(_ summary: RideSummary) -> some View {
        NavigationStack {
            RideSummaryView(summary: summary)
                .navigationTitle("Ride complete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Discard", role: .destructive) { finishedSummary = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            history.add(summary)
                            finishedSummary = nil
                        }
                    }
                }
        }
    }

    private func currentMetrics() -> LiveMetrics {
        let summary = recorder.summary
        return LiveMetrics(
            state: recorder.state,
            elapsed: summary?.activeDuration ?? 0,
            power: source.latest?.instantaneousPower.map(Int.init),
            cadence: source.latest?.instantaneousCadence,
            speed: source.latest?.instantaneousSpeed,
            heartRate: source.latest?.heartRate.flatMap { $0 == 0 ? nil : Int($0) },
            energyKilocalories: summary?.energyKilocalories ?? 0,
            distanceMeters: summary?.distanceMeters ?? 0
        )
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
        switch source.state {
        case .unavailable(let reason): reason
        case .searching: "Start pedalling to connect"
        case .connecting: "Connecting…"
        case .connected: source.latest == nil ? "Connected, waiting for data" : "Connected"
        }
    }

    private var statusColor: Color {
        switch source.state {
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
                    // Shrink rather than wrap at large Dynamic Type sizes.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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

#if DEBUG
/// A static bike source for previews and screenshots.
private final class PreviewBikeSource: BikeDataSource {
    var state: BikeConnectionState
    var latest: IndoorBikeData?
    var lastUpdate: Date?

    init(state: BikeConnectionState = .connected, latest: IndoorBikeData? = nil) {
        self.state = state
        self.latest = latest
        self.lastUpdate = latest == nil ? nil : Date()
    }
}

/// A recorder pre-filled with a ride ending about now, so the view's auto-stop
/// timer does not fire during the preview.
private func previewRecorder(seconds: Int) -> SessionRecorder {
    let base = Date().addingTimeInterval(-Double(seconds))
    let recorder = SessionRecorder()
    recorder.start(at: base)
    if let data = IndoorBikeData(indoorBikeDataPacket(
        speedKmh: 31, cadenceRpm: 88, powerW: 180, heartRate: 148)) {
        for second in 0...seconds {
            recorder.record(data, at: base.addingTimeInterval(TimeInterval(second)))
        }
    }
    return recorder
}

#Preview("Recording") {
    let latest = IndoorBikeData(indoorBikeDataPacket(
        speedKmh: 32, cadenceRpm: 90, powerW: 186, heartRate: 150))
    return RideView(source: PreviewBikeSource(latest: latest),
                    recorder: previewRecorder(seconds: 1500))
}

#Preview("Idle") {
    RideView()
}
#endif

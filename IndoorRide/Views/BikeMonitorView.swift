//
//  BikeMonitorView.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Phase 1 milestone screen: prove the bike connects and every field decodes
//  correctly on real hardware. This is a diagnostic view, not the shipping UI:
//  it deliberately shows everything, including the fields a rider never needs.
//

import SwiftUI
import IndoorRideCore

struct BikeMonitorView: View {
    @State private var bike = BikeConnection()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow
                }

                Section("Live") {
                    metric("Power", value: bike.latest?.instantaneousPower
                        .map { "\($0)" }, unit: "W")
                    metric("Cadence", value: bike.latest?.instantaneousCadence
                        .map { String(format: "%.0f", $0) }, unit: "rpm")
                    metric("Speed", value: bike.latest?.instantaneousSpeed
                        .map { String(format: "%.1f", $0) }, unit: "km/h")
                    metric("Resistance", value: bike.latest?.resistanceLevelRaw
                        .map { "\($0)" }, unit: "raw")
                    metric("Heart rate", value: bike.latest?.heartRate
                        .map { "\($0)" }, unit: "bpm")
                }

                Section("Session (reported by bike)") {
                    metric("Distance", value: bike.latest?.totalDistance
                        .map { "\($0)" }, unit: "m")
                    metric("Energy", value: bike.latest?.totalEnergy
                        .map { "\($0)" }, unit: "kcal")
                    metric("Elapsed", value: bike.latest?.elapsedTime
                        .map { "\($0)" }, unit: "s")
                }

                if let capabilities = bike.capabilities {
                    Section("Capabilities") {
                        capabilityRow("Power", capabilities.features
                            .contains(.powerMeasurement))
                        capabilityRow("Cadence", capabilities.features
                            .contains(.cadence))
                        capabilityRow("Resistance", capabilities.features
                            .contains(.resistanceLevel))
                        capabilityRow("Settable targets",
                                      capabilities.targetSettings != 0)
                    }
                }

                Section("Device") {
                    LabeledContent("Model", value: bike.modelNumber ?? "—")
                    LabeledContent("Firmware", value: bike.firmwareRevision ?? "—")
                    if let range = bike.resistanceRange {
                        LabeledContent(
                            "Resistance range",
                            value: "\(range.minimumRaw)–\(range.maximumRaw) "
                                 + "step \(range.incrementRaw)"
                        )
                    }
                }
            }
            .navigationTitle("IndoorRide")
        }
    }

    // MARK: - Rows

    private var statusRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ name: String, value: String?, unit: String) -> some View {
        LabeledContent(name) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    // Without monospaced digits the numbers jitter sideways
                    // every time a digit changes. At 1 Hz it is very visible.
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func capabilityRow(_ name: String, _ supported: Bool) -> some View {
        LabeledContent(name) {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(supported ? .green : .secondary)
        }
    }

    // MARK: - Status

    private var statusText: String {
        switch bike.state {
        case .unavailable(let reason): reason
        // The bike only powers its radio while the cranks turn, so "searching"
        // really means "waiting for you to start". Say that, rather than
        // leaving the rider staring at a spinner.
        case .searching: "Start pedalling to connect"
        case .connecting: "Connecting…"
        case .connected: bike.latest == nil
            ? "Connected, waiting for data"
            : "Connected"
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
}

#Preview {
    BikeMonitorView()
}

//
//  SettingsView.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  The one v1 setting that matters: a power scale factor to correct the bike's
//  optimistic wattage against a real power meter.
//

import SwiftUI

/// Shared key so the ride screen and settings read the same stored scale.
enum SettingsKey {
    static let powerScaleFactor = "powerScaleFactor"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.powerScaleFactor) private var powerScale = 1.0

    var body: some View {
        Form {
            Section {
                Stepper(value: $powerScale, in: 0.5...1.5, step: 0.05) {
                    LabeledContent("Power scale") {
                        Text(String(format: "%.2f", powerScale)).monospacedDigit()
                    }
                }
            } header: {
                Text("Power")
            } footer: {
                Text("The bike models power from resistance and cadence and tends "
                     + "to read 20-25% high. Lower this to match a power meter. "
                     + "Cadence and speed are measured directly and are not scaled.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}

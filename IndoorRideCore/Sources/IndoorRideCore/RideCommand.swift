//
//  RideCommand.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Control messages exchanged between the watch and phone. The phone owns the
//  recording, so the watch drives it by sending commands; the phone mirrors its
//  state back through the live-metrics stream rather than echoing commands.
//

import Foundation

/// A session control instruction sent between devices.
public enum RideCommand: String, Codable, Sendable {
    case start
    case pause
    case resume
    case stop
}

//
//  CompletedRide.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  A finished ride as kept in history: a stable identity plus its summary.
//

import Foundation

/// One saved ride in the history list.
public struct CompletedRide: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let summary: RideSummary

    public init(id: UUID = UUID(), summary: RideSummary) {
        self.id = id
        self.summary = summary
    }
}

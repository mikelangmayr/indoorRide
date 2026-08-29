//
//  RideHistory.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Persistent list of finished rides, separate from the in-progress crash
//  snapshot. The store is a protocol so tests can drive it in memory.
//

import Foundation
import IndoorRideCore
import Observation

/// Loads and saves the finished-ride list.
public protocol RideHistoryStore {
    func load() -> [CompletedRide]
    func save(_ rides: [CompletedRide])
}

/// File-backed history, one JSON array in Application Support.
public final class FileRideHistoryStore: RideHistoryStore {

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() -> FileRideHistoryStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("IndoorRide", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return FileRideHistoryStore(
            fileURL: directory.appendingPathComponent("history.json")
        )
    }

    public func load() -> [CompletedRide] {
        guard let data = try? Data(contentsOf: fileURL),
              let rides = try? decoder.decode([CompletedRide].self, from: data) else { return [] }
        return rides
    }

    public func save(_ rides: [CompletedRide]) {
        guard let data = try? encoder.encode(rides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Observable finished-ride history, newest first.
@Observable
public final class RideHistory {

    public private(set) var rides: [CompletedRide]

    private let store: RideHistoryStore

    public init(store: RideHistoryStore) {
        self.store = store
        rides = store.load()
    }

    /// Save a finished ride to the top of the list.
    public func add(_ summary: RideSummary) {
        rides.insert(CompletedRide(summary: summary), at: 0)
        store.save(rides)
    }

    public func delete(_ ride: CompletedRide) {
        rides.removeAll { $0.id == ride.id }
        store.save(rides)
    }
}

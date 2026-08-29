//
//  RideStore.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Crash-safe persistence for the in-progress ride. The recorder writes a
//  snapshot roughly once a second; on relaunch it reads the snapshot back and
//  resumes rather than losing the ride to a crash or a backgrounding kill.
//

import Foundation
import IndoorRideCore

/// Persists the single in-progress ride snapshot. Not for finished-ride history,
/// which is a separate concern handled later.
public protocol RideStore {
    /// Overwrite the stored snapshot.
    func save(_ snapshot: RideSnapshot)
    /// The last saved snapshot, or nil if none exists or it cannot be decoded.
    func load() -> RideSnapshot?
    /// Discard the stored snapshot once the ride is finished.
    func clear()
}

/// File-backed `RideStore`, one JSON document in Application Support.
public final class FileRideStore: RideStore {

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: Application Support/IndoorRide/in-progress-ride.json,
    /// creating the directory if needed.
    public static func defaultStore() -> FileRideStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("IndoorRide", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return FileRideStore(
            fileURL: directory.appendingPathComponent("in-progress-ride.json")
        )
    }

    public func save(_ snapshot: RideSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func load() -> RideSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(RideSnapshot.self, from: data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

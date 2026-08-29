//
//  RideConnectivity.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  WatchConnectivity plumbing shared by both apps. The phone is the producer:
//  it streams `LiveMetrics` at 1 Hz over `sendMessage` while reachable, mirrors
//  the latest frame into the application context as a reliable fallback, and
//  hands the final `RideSummary` over via `transferUserInfo`. The watch is the
//  consumer, publishing what it receives for the UI to observe.
//
//  Guarded on `canImport(WatchConnectivity)` so the pure-value part of the
//  package still builds on platforms without the framework.
//

#if canImport(WatchConnectivity)

import Foundation
import Observation
import WatchConnectivity

/// Cross-device link for live ride metrics and the final summary.
@Observable
@MainActor
public final class RideConnectivity: NSObject {

    /// Latest live frame received from the peer (watch side observes this).
    public private(set) var latestMetrics: LiveMetrics?
    /// Final summary delivered at ride end (watch side observes this).
    public private(set) var finalSummary: RideSummary?
    /// Whether the peer is currently reachable for immediate messages.
    public private(set) var isReachable = false

    /// Invoked when a control command arrives from the peer. The phone sets this
    /// to drive its recorder; the watch may set it to drive its workout.
    public var onCommand: (@MainActor (RideCommand) -> Void)?

    private let session: WCSession?

    public override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    // MARK: Sending (phone side)

    /// Stream one live frame. Uses `sendMessage` when reachable for immediacy,
    /// and always refreshes the application context so a watch that reconnects
    /// gets the latest state without waiting for the next message.
    public func sendLive(_ metrics: LiveMetrics) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(metrics) else { return }
        if session.isReachable {
            session.sendMessage(["live": data], replyHandler: nil, errorHandler: nil)
        }
        try? session.updateApplicationContext(["live": data])
    }

    /// Deliver the final summary reliably, even if the watch is asleep.
    public func sendFinalSummary(_ summary: RideSummary) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(summary) else { return }
        session.transferUserInfo(["summary": data])
    }

    /// Send a control command. Uses an immediate message when reachable, and
    /// falls back to a queued transfer so a start or stop is never dropped.
    public func sendCommand(_ command: RideCommand) {
        guard let session, session.activationState == .activated else { return }
        let payload = ["command": command.rawValue]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: Receiving

    /// Dispatch any of the payload kinds we understand: a live frame, a control
    /// command, or a final summary. One payload may carry more than one.
    private func handleIncoming(_ payload: [String: Any]) {
        if let data = payload["live"] as? Data,
           let metrics = try? JSONDecoder().decode(LiveMetrics.self, from: data) {
            latestMetrics = metrics
        }
        if let raw = payload["command"] as? String,
           let command = RideCommand(rawValue: raw) {
            onCommand?(command)
        }
        if let data = payload["summary"] as? Data,
           let summary = try? JSONDecoder().decode(RideSummary.self, from: data) {
            finalSummary = summary
        }
    }
}

// MARK: - WCSessionDelegate

extension RideConnectivity: WCSessionDelegate {

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in self.handleIncoming(message) }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.handleIncoming(applicationContext) }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        Task { @MainActor in self.handleIncoming(userInfo) }
    }

    // Required on iOS only; the phone can be paired with a new watch mid-life.
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}

#endif

//
//  BikeDataSource.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Abstraction over "something producing Indoor Bike Data": either the live
//  CoreBluetooth central or a synthetic replay. The ride UI observes this rather
//  than a concrete connection, so demo mode drives exactly the same code path.
//

import Foundation
import IndoorRideCore

/// A source of decoded bike notifications the UI can observe live.
public protocol BikeDataSource: AnyObject {
    var state: BikeConnectionState { get }
    /// Most recent decoded notification, or nil before the first one.
    var latest: IndoorBikeData? { get }
    /// When `latest` last changed, for driving downstream updates.
    var lastUpdate: Date? { get }
}

extension BikeConnection: BikeDataSource {}

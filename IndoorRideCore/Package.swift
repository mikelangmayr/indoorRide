// swift-tools-version: 5.9
//
//  Package.swift
//  IndoorRideCore
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  Platform-agnostic value types shared by the iOS app and the watchOS app:
//  the FTMS parser and the session model. No CoreBluetooth, no HealthKit, no
//  UI, so both targets can depend on it without pulling in platform code.
//

import PackageDescription

let package = Package(
    name: "IndoorRideCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "IndoorRideCore", targets: ["IndoorRideCore"])
    ],
    targets: [
        .target(name: "IndoorRideCore"),
        .testTarget(
            name: "IndoorRideCoreTests",
            dependencies: ["IndoorRideCore"]
        )
    ]
)

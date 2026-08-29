//
//  BikeConnection.swift
//  IndoorRide
//
//  Copyright 2026 Michael Langmayr
//  SPDX-License-Identifier: Apache-2.0
//
//  CoreBluetooth central for FTMS indoor bikes.
//
//  The Schwinn IC4 (and every bike built on the same console) only powers its
//  Bluetooth radio while the cranks are turning. It vanishes from the air when
//  you stop. That single behaviour breaks Apple's and Garmin's paired-sensor
//  models, which look for the sensor once when a workout starts and never
//  again.
//
//  This class inverts that: it scans continuously, connects the moment the bike
//  appears, and returns to scanning the instant it drops. The bike arriving on
//  the air *is* the signal that the rider started pedalling.
//
//  The IC4 also advertises Cycling Power (0x1818) without implementing it:
//  there is no such service in its GATT table. We ignore the advertisement's
//  claims and scan for Fitness Machine (0x1826), which is real.
//
//  Requires in the app target:
//    • Info.plist  → NSBluetoothAlwaysUsageDescription
//    • Capabilities → Background Modes → "Uses Bluetooth LE accessories"
//

import CoreBluetooth
import Foundation
import IndoorRideCore
import Observation

// MARK: - UUIDs

private enum BLE {
    // Services
    static let fitnessMachine = CBUUID(string: "1826")
    static let deviceInformation = CBUUID(string: "180A")

    // Fitness Machine characteristics
    static let fitnessMachineFeature = CBUUID(string: "2ACC")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let supportedResistanceRange = CBUUID(string: "2AD6")

    // Device Information characteristics
    static let modelNumber = CBUUID(string: "2A24")
    static let firmwareRevision = CBUUID(string: "2A26")

    static let servicesOfInterest = [fitnessMachine, deviceInformation]
}

// MARK: - Connection state

public enum BikeConnectionState: Equatable, Sendable {
    /// Bluetooth is off, unauthorised, or otherwise unavailable.
    case unavailable(String)
    /// Scanning. On this hardware that means: waiting for the rider to pedal.
    case searching
    case connecting
    case connected
}

// MARK: - Bike connection

@Observable
public final class BikeConnection: NSObject {

    // MARK: Published state

    public private(set) var state: BikeConnectionState = .searching

    /// Most recent decoded notification. Nil until the first packet arrives.
    public private(set) var latest: IndoorBikeData?

    /// When `latest` was received. Use this for stale-data detection: the bike
    /// notifies roughly once a second while pedalling.
    public private(set) var lastUpdate: Date?

    /// Read once per connection. Log these: when someone opens an issue saying
    /// "no cadence on my C6", firmware revision is how you tell whether they
    /// are on the same build as you.
    public private(set) var modelNumber: String?
    public private(set) var firmwareRevision: String?

    /// Read once per connection, so the app adapts to the machine rather than
    /// hardcoding assumptions about one bike.
    public private(set) var capabilities: FitnessMachineCapabilities?
    public private(set) var resistanceRange: SupportedResistanceLevelRange?

    // MARK: Private

    private var central: CBCentralManager!

    /// Strong reference is mandatory. CoreBluetooth does not retain peripherals
    /// for you. Drop this and the connection dies with no error and no
    /// callback, which is a genuinely miserable afternoon.
    private var bike: CBPeripheral?

    // MARK: Lifecycle

    public override init() {
        super.init()
        // nil queue → delegate callbacks arrive on the main queue, so mutating
        // observable state here is safe without further hopping.
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: "IndoorRide.BikeConnection"
            ]
        )
    }

    // MARK: Scanning

    private func startScanning() {
        guard central.state == .poweredOn, bike == nil else { return }
        state = .searching
        // Filtering by service UUID is not just tidiness: scanning without a
        // service filter does not work while backgrounded.
        central.scanForPeripherals(
            withServices: [BLE.fitnessMachine],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func teardown() {
        bike = nil
        latest = nil
        lastUpdate = nil
        capabilities = nil
        resistanceRange = nil
        startScanning()
    }
}

// MARK: - CBCentralManagerDelegate

extension BikeConnection: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff:
            state = .unavailable("Bluetooth is off.")
            teardownWithoutScanning()
        case .unauthorized:
            state = .unavailable("IndoorRide needs Bluetooth permission.")
        case .unsupported:
            state = .unavailable("This device has no Bluetooth LE.")
        default:
            state = .unavailable("Bluetooth unavailable.")
        }
    }

    private func teardownWithoutScanning() {
        bike = nil
        latest = nil
        lastUpdate = nil
    }

    public func centralManager(
        _ central: CBCentralManager,
        willRestoreState state: [String: Any]
    ) {
        // iOS relaunched us to hand back a connection. Reclaim the peripheral
        // so we keep receiving notifications instead of silently going deaf.
        guard let restored = state[CBCentralManagerRestoredStatePeripheralsKey]
                as? [CBPeripheral], let peripheral = restored.first else { return }
        bike = peripheral
        peripheral.delegate = self
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard bike == nil else { return }
        bike = peripheral
        peripheral.delegate = self
        central.stopScan()
        state = .connecting
        central.connect(peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        state = .connected
        peripheral.discoverServices(BLE.servicesOfInterest)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        teardown()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // Expected constantly: the bike sleeps its radio when the rider stops.
        // Not an error condition, just go back to waiting for pedals.
        teardown()
    }
}

// MARK: - CBPeripheralDelegate

extension BikeConnection: CBPeripheralDelegate {

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case BLE.fitnessMachine:
                peripheral.discoverCharacteristics(
                    [BLE.indoorBikeData,
                     BLE.fitnessMachineFeature,
                     BLE.supportedResistanceRange],
                    for: service
                )
            case BLE.deviceInformation:
                peripheral.discoverCharacteristics(
                    [BLE.modelNumber, BLE.firmwareRevision],
                    for: service
                )
            default:
                break
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case BLE.indoorBikeData:
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                // Everything else is read once and cached.
                peripheral.readValue(for: characteristic)
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BLE.indoorBikeData:
            guard let sample = IndoorBikeData(data) else { return }
            latest = sample
            lastUpdate = Date()

        case BLE.fitnessMachineFeature:
            capabilities = FitnessMachineCapabilities(data)

        case BLE.supportedResistanceRange:
            resistanceRange = SupportedResistanceLevelRange(data)

        case BLE.modelNumber:
            modelNumber = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

        case BLE.firmwareRevision:
            firmwareRevision = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

        default:
            break
        }
    }
}

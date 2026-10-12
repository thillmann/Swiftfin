//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Network

#if os(iOS)
import CoreLocation
import NetworkExtension
#endif

struct NetworkConnectionContext {

    let isSatisfied: Bool
    let interface: ServerConnectionInterface
    let wifiSSID: String?

    init(
        isSatisfied: Bool,
        interface: ServerConnectionInterface,
        wifiSSID: String?
    ) {
        self.isSatisfied = isSatisfied
        self.interface = interface
        self.wifiSSID = wifiSSID?.nilIfBlank
    }

    init(path: Network.NWPath) async {
        self = await Self.current(path: path, includeWifiSSID: true)
    }

    static func current(
        path: Network.NWPath,
        includeWifiSSID: Bool
    ) async -> NetworkConnectionContext {
        let interface = Self.interface(for: path)
        let wifiSSID: String? = if includeWifiSSID && path.status == .satisfied && interface == .wifi {
            await currentWifiSSID()
        } else {
            nil
        }

        return .init(
            isSatisfied: path.status == .satisfied,
            interface: interface,
            wifiSSID: wifiSSID
        )
    }

    static func current(includeWifiSSID: Bool) async -> NetworkConnectionContext {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "Swiftfin.NetworkConnectionContext")
        let resumeState = ContinuationResumeState()

        return await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                guard resumeState.resume() else { return }
                monitor.cancel()

                Task {
                    let context = await Self.current(
                        path: path,
                        includeWifiSSID: includeWifiSSID
                    )
                    continuation.resume(returning: context)
                }
            }

            monitor.start(queue: queue)
        }
    }

    static var unavailable: NetworkConnectionContext {
        .init(
            isSatisfied: false,
            interface: .any,
            wifiSSID: nil
        )
    }

    private static func interface(for path: Network.NWPath) -> ServerConnectionInterface {
        if path.usesInterfaceType(.wifi) {
            .wifi
        } else if path.usesInterfaceType(.cellular) {
            .cellular
        } else {
            .any
        }
    }

    @MainActor
    static func currentWifiSSID() async -> String? {
        #if os(iOS) && !targetEnvironment(simulator)
        let locationManager = CLLocationManager()
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        guard locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse
        else { return nil }
        guard locationManager.accuracyAuthorization == .fullAccuracy else { return nil }

        return await (NEHotspotNetwork.fetchCurrent())?
            .ssid
            .nilIfBlank
        #else
        return nil
        #endif
    }

    private final class ContinuationResumeState {

        private let lock = NSLock()
        private var didResume = false

        func resume() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !didResume else { return false }
            didResume = true
            return true
        }
    }
}

//
//  VPNStatusChecker.swift
//  Egress
//
//  The entry point the app, App Intents, and the widget share for running a status
//  check. The selection/egress logic lives in `AppConfig.makeSelectedProvider()`
//  and `VPNProvider`; this just wires config → provider → check.
//

import Foundation

/// Namespace for checking VPN status. Nonisolated so it (and the data layer it
/// calls — `ConfigStore` and `AppConfig.makeSelectedProvider()`) can run off the
/// main actor, e.g. from the widget extension.
nonisolated enum VPNStatusChecker {
    /// Checks the current VPN status using the given provider, or the configured
    /// selection when none is supplied.
    static func checkStatus(using provider: VPNProvider? = nil) async throws -> VPNStatus {
        let config = ConfigStore.load()
        let actualProvider = try provider ?? config.makeSelectedProvider()
        return try await actualProvider.checkStatus()
    }
}

//
//  IPCheckProvider.swift
//  Egress
//
//  A provider that checks whether the current egress IP falls within a
//  user-configured allowlist of IPv4 hosts/ranges.
//

import Foundation
import os

private let log = Logger(subsystem: "dk.montnoir.Egress", category: "IPCheckProvider")

/// Egress details for the current connection: the IP plus optional geo data
/// (mirroring what the other providers surface for the UI).
nonisolated struct EgressInfo: Equatable {
    let ipAddress: String
    let country: String?
    let city: String?
    let organization: String?
}

/// Something that can resolve the current egress IP and its geo information.
///
/// Abstracting this keeps `IPCheckProvider`'s logic free of `URLSession`, so it
/// can be tested with a stub. The real network implementation is `NetworkIPResolver`.
nonisolated protocol CurrentIPResolver {
    func resolve() async throws -> EgressInfo
}

/// Reports "connected" when the current egress IP matches the configured allowlist.
nonisolated struct IPCheckProvider: VPNProvider {
    let providerName: String

    private let matcher: IPMatcher
    private let resolver: CurrentIPResolver

    /// - Parameter name: shown as the provider name in `VPNStatus` (e.g. a
    ///   custom provider's name). Defaults to a generic label.
    init(name: String = "IP Check", rules: [String], resolver: CurrentIPResolver) throws {
        self.providerName = name
        self.matcher = try IPMatcher(rules: rules)
        self.resolver = resolver
    }

    func checkStatus() async throws -> VPNStatus {
        let info = try await resolver.resolve()
        // The allowlist is IPv4-only (v1). An egress that isn't a parseable IPv4
        // address — most realistically an IPv6 egress — simply can't match, so we
        // report "not connected" rather than throwing. The IP is still surfaced,
        // so the UI shows e.g. the v6 address alongside a calm "Not connected".
        // (Full IPv6 matching is deferred for v1. Note this also means an
        // IPv4-mapped IPv6 egress like ::ffff:a.b.c.d won't match a v4 rule.)
        let connected: Bool
        if let address = IPv4Address(parsing: info.ipAddress) {
            connected = matcher.contains(address)
        } else {
            // Two failure modes land here with the same user-facing result but
            // different significance: a normal IPv6 egress (expected on dual-stack
            // networks) vs. a genuinely malformed resolver response (e.g. an API
            // change or an injected error page). Log at debug so the latter isn't
            // completely silent; the IP is marked private to respect user privacy.
            log.debug("Egress \(info.ipAddress, privacy: .private) is not a valid IPv4 address; reporting not connected")
            connected = false
        }
        return VPNStatus(
            isConnected: connected,
            ipAddress: info.ipAddress,
            serverLocation: nil,
            country: info.country,
            city: info.city,
            organization: info.organization,
            providerName: connected ? providerName : "None",
            serverName: nil
        )
    }
}

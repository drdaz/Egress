//
//  IPCheckProvider.swift
//  Egress
//
//  A provider that checks whether the current egress IP falls within a
//  user-configured allowlist of IPv4 hosts/ranges.
//

import Foundation

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
    let providerName = "IP Check"

    private let matcher: IPMatcher
    private let resolver: CurrentIPResolver

    init(rules: [String], resolver: CurrentIPResolver) throws {
        self.matcher = try IPMatcher(rules: rules)
        self.resolver = resolver
    }

    func checkStatus() async throws -> VPNStatus {
        let info = try await resolver.resolve()
        let connected = matcher.contains(try IPv4Address(info.ipAddress))
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

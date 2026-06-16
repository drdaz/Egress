//
//  VPNProvider.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation

/// Represents the connection status from a VPN provider
nonisolated struct VPNStatus: Codable, Equatable {
    let isConnected: Bool
    let ipAddress: String
    let serverLocation: String?
    let country: String?
    let city: String?
    let organization: String?
    let providerName: String
    let serverName: String?
}

/// Presentation-related logic for VPNStatus
extension VPNStatus {
    /// "City, Country" from whichever of the two are present and non-blank,
    /// or just the one that is (e.g. a city with no country resolves to the
    /// city alone); nil when neither has a usable value. Guards against APIs
    /// that return an empty string (e.g. IVPN's `"city":""`), which would
    /// otherwise render as a dangling ", Country".
    private var cityCountry: String? {
        let parts = [city, country].compactMap(\.nonBlank)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var locationDescription: String {
        cityCountry ?? serverLocation ?? "Unknown"
    }
    
    var singleLineDescription: String {
        guard isConnected else { return "Not Connected" }
        return "Connected to \(providerName)"
    }

    /// The most specific identifier for the current egress: the provider's server
    /// name when it supplies a non-blank one (Mullvad/AirVPN), otherwise the egress
    /// IP — which is always present. Lets compact surfaces like the widget fall back
    /// to the IP instead of rendering blank when there's no usable server name.
    var serverOrIP: String {
        serverName.nonBlank ?? ipAddress
    }

    var multilineDescription: String {
        guard isConnected else { return "Not Connected" }
        
        var parts: [String] = []
        
        parts.append("Connected to \(providerName)")
        
        if let server = serverName.nonBlank {
            parts.append(server)
        } else if let location = serverLocation {
            parts.append(location)
        }
        
        if let cityCountry {
            parts.append(cityCountry)
        }

        return parts.isEmpty ? "Connected" : parts.joined(separator: "\n")
    }
}

private extension Optional where Wrapped == String {
    /// The trimmed value, or nil when absent or blank — for API fields that can
    /// arrive empty (e.g. IVPN's `"city":""`, or a `"server_name":""`). Centralises
    /// the "blank means absent" rule shared by the presentation helpers above.
    var nonBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Protocol that all VPN providers must conform to
nonisolated protocol VPNProvider {
    /// The name of the VPN provider (e.g., "Mullvad", "ProtonVPN")
    var providerName: String { get }
    
    /// Checks the current VPN connection status
    /// - Returns: A VPNStatus object with connection details
    /// - Throws: Network or parsing errors
    func checkStatus() async throws -> VPNStatus
}

/// The set of built-in VPN providers the user can choose between.
/// User-defined IP-based providers are represented separately by `CustomProvider`.
nonisolated enum VPNProviderType: String, CaseIterable, Identifiable, Codable {
    case mullvad
    case airvpn
    case ivpn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mullvad: return "Mullvad"
        case .airvpn: return "AirVPN"
        case .ivpn: return "IVPN"
        }
    }

    /// Builds the concrete built-in provider.
    func makeProvider() -> VPNProvider {
        switch self {
        case .mullvad: return MullvadProvider()
        case .airvpn: return AirVPNProvider()
        case .ivpn: return IVPNProvider()
        }
    }
}

/// A user-defined provider that reports "connected" when the current egress IP
/// falls within its allowlist of IPv4 hosts/CIDR ranges. Each one is named and
/// is selectable in the picker alongside the built-in providers.
nonisolated struct CustomProvider: Codable, Equatable, Identifiable {
    /// Stable identity, used by `SelectedProvider.custom` to reference this provider.
    let id: UUID
    var name: String
    var ranges: [String]

    init(id: UUID = UUID(), name: String, ranges: [String] = []) {
        self.id = id
        self.name = name
        self.ranges = ranges
    }
}

extension CustomProvider {
    /// Savable when it has a non-empty name and at least one valid IP/CIDR range.
    nonisolated var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !ranges.isEmpty
            && ((try? IPMatcher(rules: ranges)) != nil)
    }

    /// Builds the runtime provider that checks the current egress IP against this
    /// provider's ranges. Mirrors `VPNProviderType.makeProvider()`.
    /// - Parameter resolver: egress resolver (injected so tests can avoid the network).
    /// - Throws: if `ranges` contains a malformed IP/CIDR entry.
    nonisolated func makeProvider(resolver: CurrentIPResolver = NetworkIPResolver()) throws -> VPNProvider {
        try IPCheckProvider(name: name, rules: ranges, resolver: resolver)
    }
}

/// The user's current provider choice: either a built-in provider or one of
/// their custom IP-based providers (referenced by id).
nonisolated enum SelectedProvider: Codable, Hashable {
    case builtin(VPNProviderType)
    case custom(UUID)

    static let `default`: SelectedProvider = .builtin(.mullvad)
}

/// Error types for VPN checking
nonisolated enum VPNProviderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from VPN provider"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

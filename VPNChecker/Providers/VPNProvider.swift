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
    
    var locationDescription: String {
        if let city = city, let country = country {
            return "\(city), \(country)"
        } else if let country = country {
            return country
        } else if let location = serverLocation {
            return location
        }
        return "Unknown"
    }
    
    var singleLineDescription: String {
        guard isConnected else { return "Not Connected" }
        return "Connected to \(providerName)"
    }
    
    var multilineDescription: String {
        guard isConnected else { return "Not Connected" }
        
        var parts: [String] = []
        
        parts.append("Connected to \(providerName)")
        
        if let server = serverName {
            parts.append(server)
        } else if let location = serverLocation {
            parts.append(location)
        }
        
        if let city = city, let country = country {
            parts.append("\(city), \(country)")
        } else if let country = country {
            parts.append(country)
        }
        
        return parts.isEmpty ? "Connected" : parts.joined(separator: "\n")
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
    /// Builds the runtime provider that checks the current egress IP against this
    /// provider's ranges. Mirrors `VPNProviderType.makeProvider()`.
    /// - Parameter resolver: egress resolver (injected so tests can avoid the network).
    /// - Throws: if `ranges` contains a malformed IP/CIDR entry.
    func makeProvider(resolver: CurrentIPResolver = NetworkIPResolver()) throws -> VPNProvider {
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

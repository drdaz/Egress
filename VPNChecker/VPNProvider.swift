//
//  VPNProvider.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation

/// Represents the connection status from a VPN provider
struct VPNStatus: Codable, Equatable {
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
protocol VPNProvider {
    /// The name of the VPN provider (e.g., "Mullvad", "ProtonVPN")
    var providerName: String { get }
    
    /// Checks the current VPN connection status
    /// - Returns: A VPNStatus object with connection details
    /// - Throws: Network or parsing errors
    func checkStatus() async throws -> VPNStatus
}

/// Error types for VPN checking
enum VPNProviderError: LocalizedError {
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

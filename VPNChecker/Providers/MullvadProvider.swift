//
//  MullvadProvider.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation

/// Mullvad VPN provider implementation
nonisolated struct MullvadProvider: VPNProvider {
    let providerName = "Mullvad"
    
    private let apiURL = URL(string: "https://am.i.mullvad.net/json")!
    
    func checkStatus() async throws -> VPNStatus {
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VPNProviderError.invalidResponse
        }
        
        do {
            let mullvadResponse = try JSONDecoder().decode(MullvadResponse.self, from: data)
            return VPNStatus(
                isConnected: mullvadResponse.mullvadExitIP,
                ipAddress: mullvadResponse.ip,
                serverLocation: mullvadResponse.mullvadServerType,
                country: mullvadResponse.country,
                city: mullvadResponse.city,
                organization: mullvadResponse.organization,
                providerName: mullvadResponse.mullvadExitIP ? providerName : "None",
                serverName: mullvadResponse.mullvadExitIPHostname
            )
        } catch {
            throw VPNProviderError.decodingError(error)
        }
    }
}

// MARK: - Mullvad API Response Model

private nonisolated struct MullvadResponse: Codable {
    let ip: String
    let country: String
    let city: String
    let organization: String
    let mullvadExitIP: Bool
    let mullvadServerType: String?
    let mullvadExitIPHostname: String?
    
    enum CodingKeys: String, CodingKey {
        case ip
        case country
        case city
        case organization
        case mullvadExitIP = "mullvad_exit_ip"
        case mullvadServerType = "mullvad_server_type"
        case mullvadExitIPHostname = "mullvad_exit_ip_hostname"
    }
}

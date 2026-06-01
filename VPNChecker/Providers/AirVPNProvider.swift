//
//  AirVPNProvider.swift
//  VPNChecker
//
//  Created by Darren Black on 28/05/2026.
//

import Foundation

struct AirVPNProvider: VPNProvider {
    let providerName = "AirVPN"

    private let apiURL = URL(string: "https://airvpn.org/api/whatismyip/")!

    func checkStatus() async throws -> VPNStatus {
        let (data, response) = try await URLSession.shared.data(from: apiURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VPNProviderError.invalidResponse
        }

        do {
            let airVPNResponse = try JSONDecoder().decode(AirVPNResponse.self, from: data)
            guard airVPNResponse.result == "ok" else {
                throw VPNProviderError.invalidResponse
            }
            return VPNStatus(
                isConnected: airVPNResponse.airvpn,
                ipAddress: airVPNResponse.ip,
                serverLocation: nil,
                country: airVPNResponse.geo.name,
                city: airVPNResponse.geoAdditional?.cityName,
                organization: airVPNResponse.geoAdditional?.ispName,
                providerName: airVPNResponse.airvpn ? providerName : "None",
                serverName: nil
            )
        } catch {
            throw VPNProviderError.decodingError(error)
        }
    }
}

// MARK: - AirVPN API Response Model

private struct AirVPNResponse: Codable {
    let ip: String
    let airvpn: Bool
    let result: String
    let geo: GeoResponse
    let geoAdditional: GeoAdditionalResponse?

    enum CodingKeys: String, CodingKey {
        case ip, airvpn, result, geo
        case geoAdditional = "geo_additional"
    }
}

private struct GeoResponse: Codable {
    let code: String
    let name: String
}

private struct GeoAdditionalResponse: Codable {
    let ispName: String?
    let cityName: String?

    enum CodingKeys: String, CodingKey {
        case ispName = "isp_name"
        case cityName = "city_name"
    }
}

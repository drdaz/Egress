//
//  AirVPNProvider.swift
//  VPNChecker
//
//  Created by Darren Black on 28/05/2026.
//

import Foundation

nonisolated struct AirVPNProvider: VPNProvider {
    let providerName = "AirVPN"

    private let apiURL = URL(string: "https://airvpn.org/api/whatismyip/")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkStatus() async throws -> VPNStatus {
        let (data, response) = try await session.data(from: apiURL)

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
                country: airVPNResponse.geo?.name,
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

private nonisolated struct AirVPNResponse: Codable {
    let ip: String
    let airvpn: Bool
    let result: String
    let geo: GeoResponse?
    let geoAdditional: GeoAdditionalResponse?

    enum CodingKeys: String, CodingKey {
        case ip, airvpn, result, geo
        case geoAdditional = "geo_additional"
    }
}

private nonisolated struct GeoResponse: Codable {
    let code: String?
    let name: String?
}

private nonisolated struct GeoAdditionalResponse: Codable {
    let ispName: String?
    let cityName: String?

    enum CodingKeys: String, CodingKey {
        case ispName = "isp_name"
        case cityName = "city_name"
    }
}

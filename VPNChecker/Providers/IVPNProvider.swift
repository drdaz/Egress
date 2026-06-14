//
//  IVPNProvider.swift
//  VPNChecker
//
//  Created by Darren Black on 01/06/2026.
//

import Foundation

nonisolated struct IVPNProvider: VPNProvider {
    let providerName = "IVPN"

    private let apiURL = URL(string: "https://api.ivpn.net/v4/geo-lookup")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkStatus() async throws -> VPNStatus {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: apiURL)
        } catch {
            throw VPNProviderError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VPNProviderError.invalidResponse
        }

        do {
            let ivpnResponse = try JSONDecoder().decode(IVPNResponse.self, from: data)
            return VPNStatus(
                isConnected: ivpnResponse.isIvpnServer,
                ipAddress: ivpnResponse.ipAddress,
                serverLocation: nil,
                country: ivpnResponse.country,
                city: ivpnResponse.city,
                organization: ivpnResponse.isp ?? ivpnResponse.organization,
                providerName: ivpnResponse.isIvpnServer ? providerName : "None",
                serverName: nil
            )
        } catch {
            throw VPNProviderError.decodingError(error)
        }
    }
}

// MARK: - IVPN API Response Model

private nonisolated struct IVPNResponse: Codable {
    let ipAddress: String
    let isp: String?
    let organization: String?
    let country: String?
    let countryCode: String?
    let city: String?
    let isIvpnServer: Bool

    enum CodingKeys: String, CodingKey {
        case ipAddress = "ip_address"
        case isp
        case organization
        case country
        case countryCode = "country_code"
        case city
        case isIvpnServer
    }
}

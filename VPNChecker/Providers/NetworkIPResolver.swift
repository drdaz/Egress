//
//  NetworkIPResolver.swift
//  Egress
//
//  The real CurrentIPResolver: fetches the current egress IP and geo data over
//  HTTP. This is the only part of the IP-check feature that touches the network.
//

import Foundation

/// Resolves the current egress IP and geo information via ipwho.is (HTTPS, no API key).
nonisolated struct NetworkIPResolver: CurrentIPResolver {
    private let apiURL = URL(string: "https://ipwho.is/")!
    private let session: URLSession

    /// - Parameter session: injected so tests can supply a stubbed transport.
    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve() async throws -> EgressInfo {
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

        let decoded: IPWhoisResponse
        do {
            decoded = try JSONDecoder().decode(IPWhoisResponse.self, from: data)
        } catch {
            throw VPNProviderError.decodingError(error)
        }

        // ipwho.is signals lookup failures with `success: false` and a 200 status.
        guard decoded.success else {
            throw VPNProviderError.invalidResponse
        }

        return EgressInfo(
            ipAddress: decoded.ip,
            country: decoded.country,
            city: decoded.city,
            organization: decoded.connection?.org ?? decoded.connection?.isp
        )
    }
}

private nonisolated struct IPWhoisResponse: Codable {
    let ip: String
    let success: Bool
    let country: String?
    let city: String?
    let connection: Connection?

    struct Connection: Codable {
        let org: String?
        let isp: String?
    }
}

//
//  HTTPStubbedTests.swift
//  EgressTests
//
//  The one place we stub the HTTP transport. Every unit that touches URLSession
//  (NetworkIPResolver and the live VPN providers) is exercised here through a
//  canned URLProtocol, so the stubbing machinery lives in this file only.
//
//  All suites share StubURLProtocol.handler, so the whole tree is `.serialized`
//  to keep concurrent tests from clobbering each other's handler.
//

import Foundation
import Testing
@testable import Egress

// MARK: - HTTP stubbing infrastructure

/// A URLProtocol that returns a canned response instead of making a real request.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeStubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func respond(_ status: Int, _ body: String) -> (URLRequest) -> (HTTPURLResponse, Data) {
    { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

// MARK: - Suites

/// Serialized: every nested suite shares StubURLProtocol.handler, so none may run concurrently.
@Suite(.serialized)
struct HTTPStubbedTests {

    // MARK: NetworkIPResolver

    struct NetworkIPResolverTests {

        // A trimmed ipwho.is success payload.
        private let successBody = #"""
        {
          "ip": "203.0.113.7",
          "success": true,
          "country": "Sweden",
          "city": "Gothenburg",
          "connection": { "org": "Mullvad VPN AB", "isp": "Some ISP" }
        }
        """#

        @Test func parsesIPAndGeoFromSuccessfulResponse() async throws {
            StubURLProtocol.handler = respond(200, successBody)
            let resolver = NetworkIPResolver(session: makeStubbedSession())

            let info = try await resolver.resolve()
            #expect(info.ipAddress == "203.0.113.7")
            #expect(info.country == "Sweden")
            #expect(info.city == "Gothenburg")
            #expect(info.organization == "Mullvad VPN AB")
        }

        @Test func throwsWhenSuccessIsFalse() async {
            StubURLProtocol.handler = respond(200, #"{"ip":"","success":false,"message":"Invalid IP"}"#)
            let resolver = NetworkIPResolver(session: makeStubbedSession())
            await #expect(throws: VPNProviderError.self) {
                _ = try await resolver.resolve()
            }
        }

        @Test func throwsOnNon200() async {
            StubURLProtocol.handler = respond(500, "")
            let resolver = NetworkIPResolver(session: makeStubbedSession())
            await #expect(throws: VPNProviderError.self) {
                _ = try await resolver.resolve()
            }
        }

        @Test func throwsOnMalformedBody() async {
            StubURLProtocol.handler = respond(200, "not json")
            let resolver = NetworkIPResolver(session: makeStubbedSession())
            await #expect(throws: VPNProviderError.self) {
                _ = try await resolver.resolve()
            }
        }

        @Test func wrapsTransportError() async {
            StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let resolver = NetworkIPResolver(session: makeStubbedSession())
            await #expect(throws: VPNProviderError.self) {
                _ = try await resolver.resolve()
            }
        }
    }

    // MARK: Mullvad

    struct MullvadProviderTests {

        @Test func reportsConnectedOnMullvadExit() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip":"10.64.0.1","country":"Sweden","city":"Gothenburg","mullvad_exit_ip":true,"mullvad_server_type":"WireGuard","mullvad_exit_ip_hostname":"se-got-wg-001","organization":"Mullvad VPN AB"}
            """#)
            let status = try await MullvadProvider(session: makeStubbedSession()).checkStatus()

            #expect(status.isConnected)
            #expect(status.providerName == "Mullvad")
            #expect(status.ipAddress == "10.64.0.1")
            #expect(status.city == "Gothenburg")
            #expect(status.serverName == "se-got-wg-001")
        }

        /// Regression: Mullvad nulls `city` for IPs it can't fully geolocate (e.g. a
        /// non-Mullvad exit). The non-optional model used to throw decodingError here.
        @Test func reportsNotConnectedWhenCityIsNull() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip":"128.127.105.151","country":"The Netherlands","city":null,"mullvad_exit_ip":false,"organization":"AltusHost B.V."}
            """#)
            let status = try await MullvadProvider(session: makeStubbedSession()).checkStatus()

            #expect(!status.isConnected)
            #expect(status.providerName == "None")
            #expect(status.ipAddress == "128.127.105.151")
            #expect(status.city == nil)
        }

        @Test func throwsOnNon200() async {
            StubURLProtocol.handler = respond(500, "")
            await #expect(throws: VPNProviderError.self) {
                _ = try await MullvadProvider(session: makeStubbedSession()).checkStatus()
            }
        }

        @Test func throwsOnMalformedBody() async {
            StubURLProtocol.handler = respond(200, "not json")
            await #expect(throws: VPNProviderError.self) {
                _ = try await MullvadProvider(session: makeStubbedSession()).checkStatus()
            }
        }
    }

    // MARK: AirVPN

    struct AirVPNProviderTests {

        /// The real connected payload: `geo` present, `geo_additional` absent.
        @Test func reportsConnectedWhenGeoAdditionalAbsent() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip":"128.127.105.151","ipv4":true,"ipv6":false,"airvpn":true,"server_name":"Lupus","geo":{"code":"se","name":"Sweden"},"result":"ok"}
            """#)
            let status = try await AirVPNProvider(session: makeStubbedSession()).checkStatus()

            #expect(status.isConnected)
            #expect(status.providerName == "AirVPN")
            #expect(status.country == "Sweden")
            #expect(status.city == nil)
        }

        /// Regression: guards against a null/absent `geo` object when the API is hit
        /// from a non-AirVPN egress. The non-optional model used to throw here.
        @Test func reportsNotConnectedWhenGeoIsNull() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip":"1.2.3.4","airvpn":false,"geo":null,"result":"ok"}
            """#)
            let status = try await AirVPNProvider(session: makeStubbedSession()).checkStatus()

            #expect(!status.isConnected)
            #expect(status.providerName == "None")
            #expect(status.country == nil)
        }

        /// A non-"ok" result is a business-logic failure, not a parse failure, so
        /// it must surface as .invalidResponse — never re-wrapped as .decodingError.
        /// (VPNProviderError isn't Equatable, so match the case explicitly.)
        @Test func throwsWhenResultNotOk() async {
            StubURLProtocol.handler = respond(200, #"{"ip":"1.2.3.4","airvpn":false,"geo":null,"result":"error"}"#)
            let thrown = await #expect(throws: VPNProviderError.self) {
                _ = try await AirVPNProvider(session: makeStubbedSession()).checkStatus()
            }
            guard case .invalidResponse? = thrown else {
                Issue.record("expected .invalidResponse, got \(String(describing: thrown))")
                return
            }
        }
    }

    // MARK: IVPN

    struct IVPNProviderTests {

        @Test func reportsConnectedOnIvpnServer() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip_address":"172.98.0.1","isp":"IVPN","country":"Iceland","country_code":"IS","city":"Reykjavik","isIvpnServer":true}
            """#)
            let status = try await IVPNProvider(session: makeStubbedSession()).checkStatus()

            #expect(status.isConnected)
            #expect(status.providerName == "IVPN")
            #expect(status.ipAddress == "172.98.0.1")
            #expect(status.organization == "IVPN")
        }

        /// Core mapping: a non-IVPN egress reports not-connected with provider "None".
        @Test func reportsNotConnectedWhenNotAnIvpnServer() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip_address":"1.2.3.4","isp":"DataCamp Limited","country":"Netherlands","city":"Amsterdam","isIvpnServer":false}
            """#)
            let status = try await IVPNProvider(session: makeStubbedSession()).checkStatus()

            #expect(!status.isConnected)
            #expect(status.providerName == "None")
        }

        /// Defensive — guards the `isp ?? organization` fallback, the only branch
        /// in this provider. NOT observed from the live API: across connected and
        /// not-connected states IVPN always populates `isp` (equal to `organization`).
        /// Kept so the fallback can't silently break if that ever changes.
        @Test func usesOrganizationWhenIspMissing() async throws {
            StubURLProtocol.handler = respond(200, #"""
            {"ip_address":"1.2.3.4","isp":null,"organization":"DataCamp Limited","isIvpnServer":false}
            """#)
            let status = try await IVPNProvider(session: makeStubbedSession()).checkStatus()

            #expect(status.organization == "DataCamp Limited")
        }
    }
}

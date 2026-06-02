//
//  NetworkIPResolverTests.swift
//  EgressTests
//
//  The one place we stub the HTTP transport. NetworkIPResolver is the only
//  unit that touches URLSession, so the URLProtocol machinery lives here only.
//

import Foundation
import Testing
@testable import Egress

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

/// Serialized: all tests share StubURLProtocol.handler, so they must not run concurrently.
@Suite(.serialized)
struct NetworkIPResolverTests {

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

//
//  IPCheckProviderTests.swift
//  EgressTests
//
//  Provider-logic tests. No real networking: egress info is supplied by a
//  StubResolver so behaviour is fully determined by inputs we control.
//

import Testing
@testable import Egress

// StubResolver and info(...) live in ProviderTestSupport.swift.

struct IPCheckProviderTests {

    @Test func reportsConnectedWhenEgressIPMatches() async throws {
        let provider = try IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(info("203.0.113.7")))
        )
        let status = try await provider.checkStatus()
        #expect(status.isConnected == true)
        #expect(status.ipAddress == "203.0.113.7")
    }

    @Test func reportsNotConnectedWhenEgressIPIsOutsideRules() async throws {
        let provider = try IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(info("198.51.100.1")))
        )
        let status = try await provider.checkStatus()
        #expect(status.isConnected == false)
        #expect(status.ipAddress == "198.51.100.1")
    }

    @Test func populatesGeographicInformationFromResolver() async throws {
        let provider = try IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(
                info("203.0.113.7", country: "Sweden", city: "Gothenburg", organization: "Mullvad")
            ))
        )
        let status = try await provider.checkStatus()
        #expect(status.country == "Sweden")
        #expect(status.city == "Gothenburg")
        #expect(status.organization == "Mullvad")
        // The status should also render a meaningful location for the UI.
        #expect(status.locationDescription == "Gothenburg, Sweden")
    }

    @Test func geographicInformationIsPopulatedEvenWhenNotConnected() async throws {
        let provider = try IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(
                info("198.51.100.1", country: "Norway", city: "Oslo", organization: "SomeISP")
            ))
        )
        let status = try await provider.checkStatus()
        #expect(status.isConnected == false)
        #expect(status.country == "Norway")
        #expect(status.city == "Oslo")
    }

    @Test func providerNameReflectsMatchState() async throws {
        let matching = try IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(info("203.0.113.7")))
        )
        #expect(try await matching.checkStatus().providerName == matching.providerName)

        let nonMatching = try IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(info("198.51.100.1")))
        )
        #expect(try await nonMatching.checkStatus().providerName == "None")
    }

    @Test func propagatesResolverError() async {
        let provider = try! IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .failure(VPNProviderError.invalidResponse))
        )
        await #expect(throws: VPNProviderError.self) {
            _ = try await provider.checkStatus()
        }
    }

    @Test func throwsWhenResolvedIPIsUnparseable() async {
        let provider = try! IPCheckProvider(
            rules: ["203.0.113.0/24"],
            resolver: StubResolver(result: .success(info("not-an-ip")))
        )
        await #expect(throws: (any Error).self) {
            _ = try await provider.checkStatus()
        }
    }
}

//
//  VPNStatusLocationTests.swift
//  EgressTests
//
//  Covers VPNStatus.locationDescription / multilineDescription formatting,
//  including the empty-city case some APIs return (e.g. IVPN's "city":"").
//

import Foundation
import Testing
@testable import Egress

struct VPNStatusLocationTests {

    private func status(city: String?, country: String?, serverLocation: String? = nil) -> VPNStatus {
        VPNStatus(
            isConnected: true,
            ipAddress: "1.2.3.4",
            serverLocation: serverLocation,
            country: country,
            city: city,
            organization: nil,
            providerName: "Test",
            serverName: nil
        )
    }

    @Test func joinsCityAndCountry() {
        #expect(status(city: "Gothenburg", country: "Sweden").locationDescription == "Gothenburg, Sweden")
    }

    @Test func dropsEmptyCity() {
        #expect(status(city: "", country: "Netherlands").locationDescription == "Netherlands")
    }

    @Test func dropsWhitespaceOnlyCity() {
        #expect(status(city: "   ", country: "Netherlands").locationDescription == "Netherlands")
    }

    @Test func usesCountryWhenCityNil() {
        #expect(status(city: nil, country: "Sweden").locationDescription == "Sweden")
    }

    @Test func fallsBackToServerLocationWhenNoGeo() {
        #expect(status(city: "", country: nil, serverLocation: "WireGuard").locationDescription == "WireGuard")
    }

    @Test func unknownWhenNothingAvailable() {
        #expect(status(city: nil, country: nil).locationDescription == "Unknown")
    }

    @Test func multilineDropsEmptyCity() {
        let lines = status(city: "", country: "Netherlands").multilineDescription
        #expect(lines.contains("Netherlands"))
        #expect(!lines.contains(", Netherlands"))
    }
}

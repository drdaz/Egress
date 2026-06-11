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

    @Test func dropsEmptyCountry() {
        #expect(status(city: "Amsterdam", country: "").locationDescription == "Amsterdam")
    }

    @Test func dropsWhitespaceOnlyCountry() {
        #expect(status(city: "Amsterdam", country: "   ").locationDescription == "Amsterdam")
    }

    @Test func usesCountryWhenCityNil() {
        #expect(status(city: nil, country: "Sweden").locationDescription == "Sweden")
    }

    /// A non-blank city with no country is surfaced on its own. This is a
    /// deliberate change from the old behaviour (which fell through to
    /// serverLocation / "Unknown" unless *both* fields were present) —
    /// showing the city we have beats showing "Unknown".
    @Test func usesCityAloneWhenCountryNil() {
        #expect(status(city: "Amsterdam", country: nil).locationDescription == "Amsterdam")
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

    /// The city-alone change applies to multilineDescription too: a non-blank
    /// city with no country is appended where it was previously dropped.
    @Test func multilineUsesCityAloneWhenCountryNil() {
        let lines = status(city: "Amsterdam", country: nil).multilineDescription
        #expect(lines.contains("Amsterdam"))
    }
}

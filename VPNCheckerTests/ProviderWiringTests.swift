//
//  ProviderWiringTests.swift
//  EgressTests
//
//  Tests for the config/factory wiring of the IP-check provider.
//

import Foundation
import Testing
@testable import Egress

struct AppConfigTests {

    @Test func roundTripsRules() throws {
        let original = AppConfig(selectedProviderType: .ipCheck, ipCheckRules: ["10.0.0.0/8", "1.2.3.4"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.selectedProviderType == .ipCheck)
        #expect(decoded.ipCheckRules == ["10.0.0.0/8", "1.2.3.4"])
    }
}

struct VPNProviderTypeTests {

    @Test func ipCheckIsAnEnumerableCase() {
        #expect(VPNProviderType.allCases.contains(.ipCheck))
        #expect(VPNProviderType.ipCheck.displayName == "IP Check")
    }

    @Test func makeProviderBuildsIPCheckProviderFromValidRules() throws {
        let provider = try VPNProviderType.ipCheck.makeProvider(ipCheckRules: ["203.0.113.0/24"])
        #expect(provider is IPCheckProvider)
    }

    @Test func makeProviderThrowsOnInvalidRules() {
        #expect(throws: (any Error).self) {
            _ = try VPNProviderType.ipCheck.makeProvider(ipCheckRules: ["203.0.113.0/99"])
        }
    }

    @Test func zeroConfigProvidersStillBuild() throws {
        #expect(try VPNProviderType.mullvad.makeProvider() is MullvadProvider)
        #expect(try VPNProviderType.ivpn.makeProvider() is IVPNProvider)
        #expect(try VPNProviderType.airvpn.makeProvider() is AirVPNProvider)
    }
}

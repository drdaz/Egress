//
//  ProviderWiringTests.swift
//  EgressTests
//
//  Tests for the config/provider data model: multiple named custom providers,
//  the stored selection, persistence, and provider resolution.
//

import Foundation
import Testing
@testable import Egress

/// Test double that returns a fixed egress result instead of hitting the network.
private struct StubResolver: CurrentIPResolver {
    let result: Result<EgressInfo, Error>
    func resolve() async throws -> EgressInfo { try result.get() }
}

private func info(_ ip: String) -> EgressInfo {
    EgressInfo(ipAddress: ip, country: "Testland", city: "Testville", organization: "TestOrg")
}

/// Creates a fresh temporary directory and removes it when `body` returns.
private func withTempDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

// MARK: - Codable round-trips

struct AppConfigCodableTests {

    @Test func roundTripsBuiltinSelection() throws {
        let original = AppConfig(selection: .builtin(.ivpn))
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.selection == .builtin(.ivpn))
        #expect(decoded.customProviders.isEmpty)
    }

    @Test func roundTripsCustomProvidersAndSelection() throws {
        let home = CustomProvider(name: "Home", ranges: ["10.0.0.0/8", "1.2.3.4"])
        let office = CustomProvider(name: "Office", ranges: ["203.0.113.0/24"])
        let original = AppConfig(customProviders: [home, office], selection: .custom(office.id))

        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
        #expect(decoded.customProviders == [home, office])
        #expect(decoded.selection == .custom(office.id))
    }

    @Test func allowsDuplicateProviderNames() throws {
        let a = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        let b = CustomProvider(name: "Home", ranges: ["5.6.7.8"])
        let config = AppConfig(customProviders: [a, b], selection: .custom(b.id))

        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))

        // Distinct ids keep them separate even with identical names.
        #expect(decoded.customProviders.count == 2)
        #expect(a.id != b.id)
        #expect(decoded.selection == .custom(b.id))
    }
}

// MARK: - ConfigStore persistence

struct ConfigStoreTests {

    @Test func savesAndLoadsThroughADirectory() throws {
        try withTempDirectory { dir in
            let provider = CustomProvider(name: "Office", ranges: ["10.0.0.0/8"])
            let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))

            ConfigStore.save(config, to: dir)
            let loaded = ConfigStore.load(from: dir)

            #expect(loaded == config)
        }
    }

    @Test func returnsDefaultForEmptyDirectory() throws {
        try withTempDirectory { dir in
            #expect(ConfigStore.load(from: dir) == AppConfig.default)
        }
    }

    @Test func defaultConfigSelectsBuiltinMullvad() {
        #expect(AppConfig.default.selection == .builtin(.mullvad))
        #expect(AppConfig.default.customProviders.isEmpty)
    }
}

// MARK: - Selection resolution

struct SelectionResolutionTests {

    @Test func builtinSelectionBuildsConcreteProvider() throws {
        #expect(try AppConfig(selection: .builtin(.ivpn)).makeSelectedProvider() is IVPNProvider)
        #expect(try AppConfig(selection: .builtin(.mullvad)).makeSelectedProvider() is MullvadProvider)
        #expect(try AppConfig(selection: .builtin(.airvpn)).makeSelectedProvider() is AirVPNProvider)
    }

    @Test func customSelectionBuildsIPCheckProviderFromItsRanges() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))

        let built = try config.makeSelectedProvider(
            resolver: StubResolver(result: .success(info("203.0.113.7")))
        )
        #expect(built is IPCheckProvider)

        let status = try await built.checkStatus()
        #expect(status.isConnected == true)
        #expect(status.ipAddress == "203.0.113.7")
    }

    @Test func customProviderFactoryBuildsIPCheckProvider() throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let built = try provider.makeProvider(
            resolver: StubResolver(result: .success(info("203.0.113.7")))
        )
        #expect(built is IPCheckProvider)
    }

    @Test func connectedCustomStatusCarriesTheProviderName() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))

        let status = try await config.makeSelectedProvider(
            resolver: StubResolver(result: .success(info("203.0.113.7")))
        ).checkStatus()

        #expect(status.isConnected == true)
        #expect(status.providerName == "Home")
    }

    @Test func disconnectedCustomStatusReportsNone() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))

        let status = try await config.makeSelectedProvider(
            resolver: StubResolver(result: .success(info("198.51.100.1")))
        ).checkStatus()

        #expect(status.providerName == "None")
    }

    @Test func customSelectionWithIPOutsideRangesIsNotConnected() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))

        let built = try config.makeSelectedProvider(
            resolver: StubResolver(result: .success(info("198.51.100.1")))
        )
        #expect(try await built.checkStatus().isConnected == false)
    }

    @Test func customProviderWithNoRangesBuildsButNeverMatches() async throws {
        let provider = CustomProvider(name: "Empty", ranges: [])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))

        let built = try config.makeSelectedProvider(
            resolver: StubResolver(result: .success(info("203.0.113.7")))
        )
        #expect(try await built.checkStatus().isConnected == false)
    }

    @Test func unknownCustomIDFallsBackToDefaultProvider() throws {
        let config = AppConfig(customProviders: [], selection: .custom(UUID()))
        #expect(try config.makeSelectedProvider() is MullvadProvider)
    }

    @Test func malformedRangesThrow() {
        let provider = CustomProvider(name: "Bad", ranges: ["203.0.113.0/99"])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))
        #expect(throws: (any Error).self) {
            _ = try config.makeSelectedProvider()
        }
    }
}

// MARK: - Display name resolution

struct SelectedProviderNameTests {

    @Test func builtinNameIsTheTypeDisplayName() {
        #expect(AppConfig(selection: .builtin(.airvpn)).selectedProviderName == "AirVPN")
    }

    @Test func customNameIsTheProviderName() {
        let provider = CustomProvider(name: "Home Network", ranges: ["1.2.3.4"])
        let config = AppConfig(customProviders: [provider], selection: .custom(provider.id))
        #expect(config.selectedProviderName == "Home Network")
    }

    @Test func nameFallsBackForUnknownCustomID() {
        let config = AppConfig(customProviders: [], selection: .custom(UUID()))
        #expect(config.selectedProviderName == VPNProviderType.mullvad.displayName)
    }
}

// MARK: - Built-in provider types

struct VPNProviderTypeTests {

    @Test func builtinTypesAreTheThreeRealProviders() {
        #expect(VPNProviderType.allCases == [.mullvad, .airvpn, .ivpn])
    }

    @Test func factoryBuildsConcreteProviders() {
        #expect(VPNProviderType.mullvad.makeProvider() is MullvadProvider)
        #expect(VPNProviderType.ivpn.makeProvider() is IVPNProvider)
        #expect(VPNProviderType.airvpn.makeProvider() is AirVPNProvider)
    }
}

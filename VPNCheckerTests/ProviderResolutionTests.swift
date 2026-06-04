//
//  ProviderResolutionTests.swift
//  EgressTests
//
//  Turning a stored selection into a working provider: built-in vs custom
//  resolution, the built-in provider-type factory, and the ProviderSelection
//  observable that reloads the current selection.
//

import Foundation
import Combine
import Testing
@testable import Egress

// MARK: - Selection resolution

struct SelectionResolutionTests {

    @Test func builtinSelectionBuildsConcreteProvider() throws {
        #expect(try AppConfig(selection: .builtin(.ivpn)).makeSelectedProvider() is IVPNProvider)
        #expect(try AppConfig(selection: .builtin(.mullvad)).makeSelectedProvider() is MullvadProvider)
        #expect(try AppConfig(selection: .builtin(.airvpn)).makeSelectedProvider() is AirVPNProvider)
    }

    @Test func customSelectionBuildsIPCheckProviderFromItsRanges() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig.selecting(provider)

        let built = try config.makeSelectedProvider(resolver: StubResolver.resolving(to: "203.0.113.7"))
        #expect(built is IPCheckProvider)

        let status = try await built.checkStatus()
        #expect(status.isConnected == true)
        #expect(status.ipAddress == "203.0.113.7")
    }

    @Test func customProviderFactoryBuildsIPCheckProvider() throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let built = try provider.makeProvider(resolver: StubResolver.resolving(to: "203.0.113.7"))
        #expect(built is IPCheckProvider)
    }

    @Test func connectedCustomStatusCarriesTheProviderName() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig.selecting(provider)

        let status = try await config.makeSelectedProvider(resolver: StubResolver.resolving(to: "203.0.113.7")).checkStatus()

        #expect(status.isConnected == true)
        #expect(status.providerName == "Home")
    }

    @Test func disconnectedCustomStatusReportsNone() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig.selecting(provider)

        let status = try await config.makeSelectedProvider(resolver: StubResolver.resolving(to: "198.51.100.1")).checkStatus()

        #expect(status.providerName == "None")
    }

    @Test func customSelectionWithIPOutsideRangesIsNotConnected() async throws {
        let provider = CustomProvider(name: "Home", ranges: ["203.0.113.0/24"])
        let config = AppConfig.selecting(provider)

        let built = try config.makeSelectedProvider(resolver: StubResolver.resolving(to: "198.51.100.1"))
        #expect(try await built.checkStatus().isConnected == false)
    }

    @Test func customProviderWithNoRangesBuildsButNeverMatches() async throws {
        let provider = CustomProvider(name: "Empty", ranges: [])
        let config = AppConfig.selecting(provider)

        let built = try config.makeSelectedProvider(resolver: StubResolver.resolving(to: "203.0.113.7"))
        #expect(try await built.checkStatus().isConnected == false)
    }

    @Test func unknownCustomIDFallsBackToDefaultProvider() throws {
        let config = AppConfig(customProviders: [], selection: .custom(UUID()))
        #expect(try config.makeSelectedProvider() is MullvadProvider)
    }

    @Test func malformedRangesThrow() {
        let provider = CustomProvider(name: "Bad", ranges: ["203.0.113.0/99"])
        let config = AppConfig.selecting(provider)
        #expect(throws: (any Error).self) {
            _ = try config.makeSelectedProvider()
        }
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

// MARK: - Auto-load: ProviderSelection.reload

@MainActor
struct ProviderSelectionReloadTests {

    @Test func reloadPicksUpChangedSelection() {
        let selection = ProviderSelection(load: { AppConfig(selection: .builtin(.mullvad)) })
        #expect(selection.selection == .builtin(.mullvad))

        let home = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        selection.reload(using: { AppConfig.selecting(home) })

        #expect(selection.selection == .custom(home.id))
    }

    @Test func reloadEmitsOnceWhenSelectionChanges() {
        let selection = ProviderSelection(load: { AppConfig(selection: .builtin(.mullvad)) })
        var emissions = 0
        let cancellable = selection.$selection.dropFirst().sink { _ in emissions += 1 }
        defer { cancellable.cancel() }

        selection.reload(using: { AppConfig(selection: .builtin(.ivpn)) })

        #expect(emissions == 1)
        #expect(selection.selection == .builtin(.ivpn))
    }

    @Test func reloadIsNoOpWhenSelectionUnchanged() {
        let selection = ProviderSelection(load: { AppConfig(selection: .builtin(.ivpn)) })
        var emissions = 0
        let cancellable = selection.$selection.dropFirst().sink { _ in emissions += 1 }
        defer { cancellable.cancel() }

        selection.reload(using: { AppConfig(selection: .builtin(.ivpn)) })

        #expect(emissions == 0)
    }

    @Test func refreshNotifiesObservers() {
        let selection = ProviderSelection(load: { .default })
        var emissions = 0
        let cancellable = selection.objectWillChange.sink { _ in emissions += 1 }
        defer { cancellable.cancel() }

        selection.refresh()

        #expect(emissions == 1)
    }
}

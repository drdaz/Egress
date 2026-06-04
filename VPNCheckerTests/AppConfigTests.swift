//
//  AppConfigTests.swift
//  EgressTests
//
//  The AppConfig value type and its derived data: Codable round-trips,
//  upsert/remove mutations, the settings picker list, the selected provider
//  name, and CustomProvider validity.
//

import Foundation
import Testing
@testable import Egress

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

// MARK: - Save: upsert into config

struct AppConfigUpsertTests {

    @Test func upsertAppendsNewProvider() {
        var config = AppConfig.default
        let p = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        config.upsert(p)
        #expect(config.customProviders == [p])
    }

    @Test func upsertReplacesExistingByID() {
        let original = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        var config = AppConfig(customProviders: [original], selection: .builtin(.mullvad))
        let edited = CustomProvider(id: original.id, name: "Home HQ", ranges: ["1.2.3.4", "5.6.7.8"])
        config.upsert(edited)
        #expect(config.customProviders.count == 1)
        #expect(config.customProviders.first == edited)
    }
}

// MARK: - Remove

struct AppConfigRemoveTests {

    @Test func removesProviderByID() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        let b = CustomProvider(name: "B", ranges: ["2.2.2.2"])
        var config = AppConfig(customProviders: [a, b], selection: .builtin(.mullvad))
        config.removeProvider(id: a.id)
        #expect(config.customProviders.map(\.id) == [b.id])
    }

    @Test func resetsSelectionWhenRemovingSelectedProvider() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        var config = AppConfig.selecting(a)
        config.removeProvider(id: a.id)
        #expect(config.customProviders.isEmpty)
        #expect(config.selection == .default)
    }

    @Test func keepsSelectionWhenRemovingADifferentProvider() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        let b = CustomProvider(name: "B", ranges: ["2.2.2.2"])
        var config = AppConfig(customProviders: [a, b], selection: .custom(b.id))
        config.removeProvider(id: a.id)
        #expect(config.selection == .custom(b.id))
    }

    @Test func saverRemovePersists() throws {
        try withTempDirectory { dir in
            let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
            _ = try CustomProviderSaver.save(a, in: dir)

            CustomProviderSaver.remove(id: a.id, in: dir)

            #expect(ConfigStore.load(from: dir).customProviders.isEmpty)
        }
    }
}

// MARK: - Settings picker items

struct ProviderPickerItemsTests {

    @Test func listsBuiltinsWhenNoCustomProviders() {
        let items = AppConfig.default.pickerItems
        #expect(items.map(\.selection) == [.builtin(.mullvad), .builtin(.airvpn), .builtin(.ivpn)])
        #expect(items.map(\.label) == ["Mullvad", "AirVPN", "IVPN"])
    }

    @Test func appendsCustomProvidersAfterBuiltins() {
        let home = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        let office = CustomProvider(name: "Office", ranges: ["5.6.7.8"])
        let config = AppConfig(customProviders: [home, office], selection: .builtin(.mullvad))

        let items = config.pickerItems

        #expect(items.count == 5)
        #expect(items.suffix(2).map(\.selection) == [.custom(home.id), .custom(office.id)])
        #expect(items.suffix(2).map(\.label) == ["Home", "Office"])
    }
}

// MARK: - Display name resolution

struct SelectedProviderNameTests {

    @Test func builtinNameIsTheTypeDisplayName() {
        #expect(AppConfig(selection: .builtin(.airvpn)).selectedProviderName == "AirVPN")
    }

    @Test func customNameIsTheProviderName() {
        let provider = CustomProvider(name: "Home Network", ranges: ["1.2.3.4"])
        #expect(AppConfig.selecting(provider).selectedProviderName == "Home Network")
    }

    @Test func nameFallsBackForUnknownCustomID() {
        let config = AppConfig(customProviders: [], selection: .custom(UUID()))
        #expect(config.selectedProviderName == VPNProviderType.mullvad.displayName)
    }
}

// MARK: - Save: provider validity

struct CustomProviderValidityTests {

    @Test func validWithNameAndValidRanges() {
        #expect(CustomProvider(name: "Home", ranges: ["10.0.0.0/8"]).isValid)
    }

    @Test func invalidWhenNameBlank() {
        #expect(!CustomProvider(name: "   ", ranges: ["1.2.3.4"]).isValid)
    }

    @Test func invalidWhenNoRanges() {
        #expect(!CustomProvider(name: "Home", ranges: []).isValid)
    }

    @Test func invalidWhenRangeMalformed() {
        #expect(!CustomProvider(name: "Home", ranges: ["nope"]).isValid)
    }
}

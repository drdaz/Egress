//
//  ProviderWiringTests.swift
//  EgressTests
//
//  Tests for the config/provider data model: multiple named custom providers,
//  the stored selection, persistence, and provider resolution.
//

import Foundation
import Combine
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

// MARK: - Auto-load: ProviderSelection.reload

@MainActor
struct ProviderSelectionReloadTests {

    @Test func reloadPicksUpChangedSelection() {
        let selection = ProviderSelection(load: { AppConfig(selection: .builtin(.mullvad)) })
        #expect(selection.selection == .builtin(.mullvad))

        let home = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        selection.reload(using: { AppConfig(customProviders: [home], selection: .custom(home.id)) })

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

// MARK: - Save: persistence

struct CustomProviderSaverTests {

    @Test func savingNewProviderPersistsIt() throws {
        try withTempDirectory { dir in
            let p = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
            let updated = try CustomProviderSaver.save(p, in: dir)
            #expect(updated.customProviders == [p])
            #expect(ConfigStore.load(from: dir).customProviders == [p])
        }
    }

    @Test func savingExistingProviderUpdatesInPlace() throws {
        try withTempDirectory { dir in
            let original = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
            _ = try CustomProviderSaver.save(original, in: dir)
            let edited = CustomProvider(id: original.id, name: "Home HQ", ranges: ["9.9.9.9"])
            _ = try CustomProviderSaver.save(edited, in: dir)

            let loaded = ConfigStore.load(from: dir)
            #expect(loaded.customProviders.count == 1)
            #expect(loaded.customProviders.first == edited)
        }
    }

    @Test func savingInvalidProviderThrowsAndPersistsNothing() throws {
        try withTempDirectory { dir in
            #expect(throws: (any Error).self) {
                _ = try CustomProviderSaver.save(CustomProvider(name: "", ranges: []), in: dir)
            }
            #expect(ConfigStore.load(from: dir) == AppConfig.default)
        }
    }
}

// MARK: - iCloud: merge / precedence

struct AppConfigMergeTests {

    @Test func unionsCloudProvidersKeepingLocalSelection() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        let b = CustomProvider(name: "B", ranges: ["2.2.2.2"])
        let local = AppConfig(customProviders: [a], selection: .custom(a.id))

        let merged = local.mergingCustomProviders([b])

        #expect(Set(merged.customProviders.map(\.id)) == Set([a.id, b.id]))
        #expect(merged.selection == .custom(a.id))   // selection is per-device, stays local
    }

    @Test func cloudWinsOnIDConflict() {
        let id = UUID()
        let local = AppConfig(customProviders: [CustomProvider(id: id, name: "Old", ranges: ["1.1.1.1"])],
                              selection: .builtin(.mullvad))

        let merged = local.mergingCustomProviders([CustomProvider(id: id, name: "New", ranges: ["3.3.3.3"])])

        #expect(merged.customProviders.count == 1)
        #expect(merged.customProviders.first?.name == "New")
        #expect(merged.selection == .builtin(.mullvad))   // local selection untouched
    }

    @Test func selectionNeverComesFromCloud() {
        let local = AppConfig(customProviders: [], selection: .builtin(.airvpn))
        let merged = local.mergingCustomProviders([CustomProvider(name: "Cloud", ranges: ["9.9.9.9"])])
        #expect(merged.selection == .builtin(.airvpn))
    }

    @Test func encodedProvidersStayWithinKVSLimits() throws {
        let providers = (0..<100).map { CustomProvider(name: "Provider \($0)", ranges: ["10.0.\($0).0/24"]) }
        let data = try JSONEncoder().encode(providers)
        #expect(data.count < 1_000_000)   // NSUbiquitousKeyValueStore per-value limit
    }
}

// MARK: - iCloud: sync coordinator

private final class FakeKVStore: KeyValueSyncing, @unchecked Sendable {
    var storage: [String: Data] = [:]
    private let subject = PassthroughSubject<Void, Never>()
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
    @discardableResult func synchronize() -> Bool { true }
    var externalChanges: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    func fireExternalChange() { subject.send() }
}

@MainActor
struct CloudConfigSyncTests {

    @Test func pushWritesEncodedLocalProviders() throws {
        let store = FakeKVStore()
        let providers = [CustomProvider(name: "Home", ranges: ["1.2.3.4"])]
        let local = AppConfig(customProviders: providers, selection: .builtin(.mullvad))
        let sync = CloudConfigSync(store: store, load: { local }, persist: { _ in }, onApplied: {})

        sync.push()

        let data = try #require(store.storage[CloudConfigSync.key])
        #expect(try JSONDecoder().decode([CustomProvider].self, from: data) == providers)
    }

    @Test func applyCloudSeedsCloudWhenEmpty() {
        let store = FakeKVStore()
        let local = AppConfig(customProviders: [CustomProvider(name: "Home", ranges: ["1.2.3.4"])],
                              selection: .builtin(.ivpn))
        var persisted: AppConfig?
        let sync = CloudConfigSync(store: store, load: { local }, persist: { persisted = $0 }, onApplied: {})

        sync.applyCloud()

        #expect(store.storage[CloudConfigSync.key] != nil)   // local providers pushed up
        #expect(persisted == nil)                            // nothing pulled down
    }

    @Test func applyCloudMergesProvidersKeepingLocalSelection() throws {
        let store = FakeKVStore()
        let cloudProvider = CustomProvider(name: "Cloud", ranges: ["9.9.9.9"])
        store.storage[CloudConfigSync.key] = try JSONEncoder().encode([cloudProvider])
        let localProvider = CustomProvider(name: "Local", ranges: ["1.1.1.1"])
        let local = AppConfig(customProviders: [localProvider], selection: .builtin(.mullvad))

        var persisted: AppConfig?
        var applied = 0
        let sync = CloudConfigSync(store: store, load: { local }, persist: { persisted = $0 }, onApplied: { applied += 1 })

        sync.applyCloud()

        let result = try #require(persisted)
        #expect(Set(result.customProviders.map(\.id)) == Set([cloudProvider.id, localProvider.id]))
        #expect(result.selection == .builtin(.mullvad))   // selection stays local
        #expect(applied == 1)
    }

    @Test func externalChangeTriggersApply() throws {
        let store = FakeKVStore()
        let cloudProvider = CustomProvider(name: "Cloud", ranges: ["9.9.9.9"])
        store.storage[CloudConfigSync.key] = try JSONEncoder().encode([cloudProvider])

        var applied = 0
        let sync = CloudConfigSync(store: store, load: { .default }, persist: { _ in }, onApplied: { applied += 1 })

        sync.start()
        let afterStart = applied
        store.fireExternalChange()

        #expect(applied == afterStart + 1)
    }
}

// MARK: - Editor: provider choices (picker incl. "Add Custom")

struct ProviderChoiceItemsTests {

    @Test func defaultListsBuiltinsThenAddCustom() {
        let items = AppConfig.default.providerChoiceItems
        #expect(items.map(\.choice) == [
            .selection(.builtin(.mullvad)),
            .selection(.builtin(.airvpn)),
            .selection(.builtin(.ivpn)),
            .addCustom,
        ])
        #expect(items.last?.label == "Add Custom…")
    }

    @Test func customProvidersAppearBeforeAddCustom() {
        let home = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        let config = AppConfig(customProviders: [home], selection: .builtin(.mullvad))
        let items = config.providerChoiceItems
        #expect(items.map(\.choice) == [
            .selection(.builtin(.mullvad)),
            .selection(.builtin(.airvpn)),
            .selection(.builtin(.ivpn)),
            .selection(.custom(home.id)),
            .addCustom,
        ])
    }
}

// MARK: - Editor: conditional-display mapping

struct ProviderEditorModeTests {

    @Test func builtinSelectionHidesEditor() {
        #expect(ProviderEditorMode(choice: .selection(.builtin(.mullvad))) == .hidden)
    }

    @Test func customSelectionEditsThatProvider() {
        let id = UUID()
        #expect(ProviderEditorMode(choice: .selection(.custom(id))) == .editing(id))
    }

    @Test func addCustomCreatesNew() {
        #expect(ProviderEditorMode(choice: .addCustom) == .creating)
    }
}

// MARK: - Editor: model behaviour

@MainActor
struct CustomProviderEditorModelTests {

    @Test func addsValidHostAndCIDR() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "203.0.113.7"; m.addRange()
        m.rangeInput = "10.0.0.0/8"; m.addRange()
        #expect(m.ranges == ["203.0.113.7", "10.0.0.0/8"])
        #expect(m.rangeInput == "")
        #expect(m.rangeInputError == nil)
    }

    @Test func trimsWhitespaceWhenAdding() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "  1.2.3.4 "; m.addRange()
        #expect(m.ranges == ["1.2.3.4"])
    }

    @Test func rejectsInvalidRange() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "not-an-ip"; m.addRange()
        #expect(m.ranges.isEmpty)
        #expect(m.rangeInputError != nil)
        #expect(m.rangeInput == "not-an-ip")   // input kept so the user can fix it
    }

    @Test func rejectsMalformedCIDR() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "10.0.0.0/99"; m.addRange()
        #expect(m.ranges.isEmpty)
        #expect(m.rangeInputError != nil)
    }

    @Test func ignoresEmptyInput() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "   "; m.addRange()
        #expect(m.ranges.isEmpty)
        #expect(m.rangeInputError == nil)
    }

    @Test func rejectsDuplicateRange() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "1.2.3.4"; m.addRange()
        m.rangeInput = "1.2.3.4"; m.addRange()
        #expect(m.ranges == ["1.2.3.4"])
        #expect(m.rangeInputError != nil)
    }

    @Test func removesRange() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "1.2.3.4"; m.addRange()
        m.rangeInput = "5.6.7.8"; m.addRange()
        m.removeRange(at: IndexSet(integer: 0))
        #expect(m.ranges == ["5.6.7.8"])
    }

    @Test func canSaveRequiresNameAndRanges() {
        let m = CustomProviderEditorModel()
        #expect(m.canSave == false)
        m.name = "Home"
        #expect(m.canSave == false)            // no ranges yet
        m.rangeInput = "1.2.3.4"; m.addRange()
        #expect(m.canSave == true)
        m.name = "   "
        #expect(m.canSave == false)            // whitespace-only name
    }

    @Test func newDraftHasFreshIDAndTrimmedName() {
        let m = CustomProviderEditorModel()
        m.startNew()
        m.name = "  Home  "
        m.rangeInput = "1.2.3.4"; m.addRange()
        let draft = m.makeDraft()
        #expect(draft.name == "Home")
        #expect(draft.ranges == ["1.2.3.4"])
    }

    @Test func editingDraftPreservesID() {
        let existing = CustomProvider(name: "Office", ranges: ["10.0.0.0/8"])
        let m = CustomProviderEditorModel()
        m.startEditing(existing)
        m.name = "Office HQ"
        let draft = m.makeDraft()
        #expect(draft.id == existing.id)
        #expect(draft.name == "Office HQ")
        #expect(draft.ranges == ["10.0.0.0/8"])
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

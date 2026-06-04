//
//  ConfigPersistenceTests.swift
//  EgressTests
//
//  Where the config lives: on-disk persistence via ConfigStore /
//  CustomProviderSaver, last-write-wins adoption of a cloud provider list, and
//  the CloudConfigSync coordinator that drives iCloud key-value sync.
//

import Foundation
import Testing
@testable import Egress

// MARK: - ConfigStore persistence

struct ConfigStoreTests {

    @Test func savesAndLoadsThroughADirectory() throws {
        try withTempDirectory { dir in
            let provider = CustomProvider(name: "Office", ranges: ["10.0.0.0/8"])
            let config = AppConfig.selecting(provider)

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

// MARK: - iCloud: last-write-wins adoption

struct CustomProvidersAdoptTests {

    @Test func adoptsCloudListWholesale() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        let b = CustomProvider(name: "B", ranges: ["2.2.2.2"])
        let local = AppConfig(customProviders: [a], selection: .custom(a.id),
                              providersModifiedAt: Date(timeIntervalSince1970: 100))
        let cloud = SyncedProviders(providers: [b], modifiedAt: Date(timeIntervalSince1970: 200))

        let result = local.adoptingCustomProviders(cloud)

        #expect(result.customProviders == [b])   // wholesale replace, NOT a union
        #expect(result.providersModifiedAt == cloud.modifiedAt)
    }

    @Test func keepsLocalSelectionWhenStillPresent() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        let local = AppConfig.selecting(a)
        let cloud = SyncedProviders(providers: [a, CustomProvider(name: "B", ranges: ["2.2.2.2"])],
                                    modifiedAt: Date(timeIntervalSince1970: 200))

        #expect(local.adoptingCustomProviders(cloud).selection == .custom(a.id))
    }

    @Test func fallsBackSelectionWhenAdoptedListDropsIt() {
        let a = CustomProvider(name: "A", ranges: ["1.1.1.1"])
        let local = AppConfig.selecting(a)
        let cloud = SyncedProviders(providers: [], modifiedAt: Date(timeIntervalSince1970: 200))

        let result = local.adoptingCustomProviders(cloud)
        #expect(result.customProviders.isEmpty)
        #expect(result.selection == .default)
    }

    @Test func builtinSelectionUnaffected() {
        let local = AppConfig(customProviders: [], selection: .builtin(.ivpn))
        let cloud = SyncedProviders(providers: [CustomProvider(name: "B", ranges: ["2.2.2.2"])],
                                    modifiedAt: Date(timeIntervalSince1970: 200))
        #expect(local.adoptingCustomProviders(cloud).selection == .builtin(.ivpn))
    }

    @Test func encodedPayloadStaysWithinKVSLimits() throws {
        let providers = (0..<100).map { CustomProvider(name: "Provider \($0)", ranges: ["10.0.\($0).0/24"]) }
        let data = try JSONEncoder().encode(SyncedProviders(providers: providers, modifiedAt: Date(timeIntervalSince1970: 0)))
        #expect(data.count < 1_000_000)   // NSUbiquitousKeyValueStore per-value limit
    }
}

// MARK: - iCloud: sync coordinator

@MainActor
struct CloudConfigSyncTests {

    private func cloudPayload(_ providers: [CustomProvider], at seconds: TimeInterval) throws -> Data {
        try JSONEncoder().encode(SyncedProviders(providers: providers, modifiedAt: Date(timeIntervalSince1970: seconds)))
    }

    @Test func pushWritesProvidersWithTimestamp() throws {
        let store = FakeKVStore()
        let providers = [CustomProvider(name: "Home", ranges: ["1.2.3.4"])]
        let local = AppConfig(customProviders: providers, selection: .builtin(.mullvad),
                              providersModifiedAt: Date(timeIntervalSince1970: 500))
        let sync = CloudConfigSync(store: store, load: { local }, persist: { _ in }, onApplied: {})

        sync.push()

        let data = try #require(store.storage[CloudConfigSync.key])
        let payload = try JSONDecoder().decode(SyncedProviders.self, from: data)
        #expect(payload.providers == providers)
        #expect(payload.modifiedAt == Date(timeIntervalSince1970: 500))
    }

    @Test func applyCloudAdoptsWhenCloudIsNewer() throws {
        let store = FakeKVStore()
        let cloudProvider = CustomProvider(name: "Cloud", ranges: ["9.9.9.9"])
        store.storage[CloudConfigSync.key] = try cloudPayload([cloudProvider], at: 200)
        let local = AppConfig(customProviders: [CustomProvider(name: "Local", ranges: ["1.1.1.1"])],
                              selection: .builtin(.mullvad), providersModifiedAt: Date(timeIntervalSince1970: 100))

        var persisted: AppConfig?
        var applied = 0
        let sync = CloudConfigSync(store: store, load: { local }, persist: { persisted = $0 }, onApplied: { applied += 1 })

        sync.applyCloud()

        #expect(persisted?.customProviders == [cloudProvider])   // wholesale replace
        #expect(applied == 1)
    }

    @Test func applyCloudPushesWhenLocalIsNewer() throws {
        let store = FakeKVStore()
        store.storage[CloudConfigSync.key] = try cloudPayload([], at: 100)
        let localProvider = CustomProvider(name: "Local", ranges: ["1.1.1.1"])
        let local = AppConfig(customProviders: [localProvider], selection: .builtin(.mullvad),
                              providersModifiedAt: Date(timeIntervalSince1970: 300))

        var persisted: AppConfig?
        var applied = 0
        let sync = CloudConfigSync(store: store, load: { local }, persist: { persisted = $0 }, onApplied: { applied += 1 })

        sync.applyCloud()

        let payload = try JSONDecoder().decode(SyncedProviders.self, from: try #require(store.storage[CloudConfigSync.key]))
        #expect(payload.providers == [localProvider])   // local pushed up
        #expect(persisted == nil)                       // nothing pulled down
        #expect(applied == 0)
    }

    @Test func applyCloudSeedsCloudWhenEmpty() {
        let store = FakeKVStore()
        let local = AppConfig(customProviders: [CustomProvider(name: "Home", ranges: ["1.2.3.4"])],
                              selection: .builtin(.ivpn), providersModifiedAt: Date(timeIntervalSince1970: 100))
        var persisted: AppConfig?
        let sync = CloudConfigSync(store: store, load: { local }, persist: { persisted = $0 }, onApplied: {})

        sync.applyCloud()

        #expect(store.storage[CloudConfigSync.key] != nil)
        #expect(persisted == nil)
    }

    @Test func deletionPropagatesWithoutResurrection() throws {
        // Cloud (from another device) is newer with the provider removed; this
        // device still has it locally. The deletion must stick.
        let store = FakeKVStore()
        store.storage[CloudConfigSync.key] = try cloudPayload([], at: 200)
        let stillHas = CustomProvider(name: "X", ranges: ["1.1.1.1"])
        let local = AppConfig(customProviders: [stillHas], selection: .custom(stillHas.id),
                              providersModifiedAt: Date(timeIntervalSince1970: 100))

        var persisted: AppConfig?
        let sync = CloudConfigSync(store: store, load: { local }, persist: { persisted = $0 }, onApplied: {})

        sync.applyCloud()

        #expect(persisted?.customProviders.isEmpty == true)   // gone, not resurrected
        #expect(persisted?.selection == .default)             // selection fell back
    }

    @Test func externalChangeTriggersApply() throws {
        let store = FakeKVStore()
        store.storage[CloudConfigSync.key] = try cloudPayload([CustomProvider(name: "Cloud", ranges: ["9.9.9.9"])], at: 999)

        var applied = 0
        let sync = CloudConfigSync(store: store, load: { .default }, persist: { _ in }, onApplied: { applied += 1 })

        sync.start()
        let afterStart = applied
        store.fireExternalChange()

        #expect(applied == afterStart + 1)
    }
}

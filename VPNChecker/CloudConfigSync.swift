//
//  CloudConfigSync.swift
//  Egress
//
//  Syncs the app config across the user's devices via iCloud key-value storage.
//  The store is abstracted behind `KeyValueSyncing` so the coordinator can be
//  unit-tested with an in-memory fake (real iCloud can't run headlessly).
//
//  Requires the "iCloud → Key-value storage" capability to actually sync; without
//  it the code still builds and runs, it just won't propagate between devices.
//

import Foundation
import Combine
import WidgetKit

/// Minimal façade over `NSUbiquitousKeyValueStore` so it can be faked in tests.
nonisolated protocol KeyValueSyncing {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
    /// Fires when the store changes because of another device / the server.
    var externalChanges: AnyPublisher<Void, Never> { get }
}

/// Real implementation backed by iCloud key-value storage.
nonisolated final class UbiquitousKeyValueStore: KeyValueSyncing {
    private let store = NSUbiquitousKeyValueStore.default

    func data(forKey key: String) -> Data? { store.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { store.set(data, forKey: key) }
    @discardableResult func synchronize() -> Bool { store.synchronize() }

    var externalChanges: AnyPublisher<Void, Never> {
        NotificationCenter.default
            .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

/// Mirrors the local config to iCloud on change, and folds external iCloud
/// changes back into the local config (then triggers the same-device reload path).
@MainActor
final class CloudConfigSync {
    /// Only the custom providers are synced; the selected provider stays per-device.
    static let key = "customProviders.v1"

    static let shared = CloudConfigSync(
        store: UbiquitousKeyValueStore(),
        onApplied: {
            ProviderSelection.shared.reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
    )

    private let store: KeyValueSyncing
    private let load: () -> AppConfig
    private let persist: (AppConfig) -> Void
    private let onApplied: () -> Void
    private var cancellable: AnyCancellable?

    init(
        store: KeyValueSyncing,
        load: @escaping () -> AppConfig = ConfigStore.load,
        persist: @escaping (AppConfig) -> Void = ConfigStore.save,
        onApplied: @escaping () -> Void = {}
    ) {
        self.store = store
        self.load = load
        self.persist = persist
        self.onApplied = onApplied
    }

    /// Begin syncing: reconcile with the cloud once, then watch for external changes.
    func start() {
        _ = store.synchronize()
        applyCloud()
        cancellable = store.externalChanges.sink { [weak self] in
            MainActor.assumeIsolated { self?.applyCloud() }
        }
    }

    /// Mirror the current local custom providers up to iCloud.
    func push() {
        guard let data = try? JSONEncoder().encode(load().customProviders) else { return }
        store.set(data, forKey: Self.key)
        _ = store.synchronize()
    }

    /// Pull the cloud providers, merge them into local (keeping the local
    /// selection), persist, and notify. If the cloud has nothing yet, seed it.
    func applyCloud() {
        guard let data = store.data(forKey: Self.key),
              let cloudProviders = try? JSONDecoder().decode([CustomProvider].self, from: data) else {
            push()
            return
        }
        persist(load().mergingCustomProviders(cloudProviders))
        onApplied()
    }
}

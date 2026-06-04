//
//  VPNStatusChecker.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation
import os
import Combine

/// Persisted app configuration written as JSON in the shared App Group container.
nonisolated struct AppConfig: Codable, Equatable {
    /// User-defined IP-based providers, each selectable in the picker.
    var customProviders: [CustomProvider]
    /// The currently selected provider (built-in or custom).
    var selection: SelectedProvider

    static let `default` = AppConfig(customProviders: [], selection: .default)

    init(customProviders: [CustomProvider] = [], selection: SelectedProvider = .default) {
        self.customProviders = customProviders
        self.selection = selection
    }
}

extension AppConfig {
    /// Looks up a custom provider by id.
    func customProvider(withID id: UUID) -> CustomProvider? {
        customProviders.first { $0.id == id }
    }

    /// Inserts the provider, or replaces the existing one with the same id.
    nonisolated mutating func upsert(_ provider: CustomProvider) {
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            customProviders[index] = provider
        } else {
            customProviders.append(provider)
        }
    }

    /// Removes the custom provider with the given id. If it was the active
    /// selection, falls back to the default provider.
    nonisolated mutating func removeProvider(id: UUID) {
        customProviders.removeAll { $0.id == id }
        if selection == .custom(id) {
            selection = .default
        }
    }

    /// Fold cloud-synced custom providers into this config. Providers are unioned
    /// by id (cloud wins on a conflict). The selection is intentionally NOT synced —
    /// it stays per-device, so the local selection is always kept.
    nonisolated func mergingCustomProviders(_ cloudProviders: [CustomProvider]) -> AppConfig {
        var providers = cloudProviders
        for local in customProviders where !providers.contains(where: { $0.id == local.id }) {
            providers.append(local)
        }
        return AppConfig(customProviders: providers, selection: selection)
    }

    /// Display name for the current selection. Falls back to the default built-in's
    /// name when a `.custom` selection references an id that no longer exists.
    var selectedProviderName: String {
        switch selection {
        case .builtin(let type):
            return type.displayName
        case .custom(let id):
            return customProvider(withID: id)?.name ?? VPNProviderType.mullvad.displayName
        }
    }

    /// Builds the concrete provider for the current selection.
    /// - Parameter resolver: egress resolver used by custom IP-based providers
    ///   (injected so tests can avoid the network).
    /// - Throws: if a selected custom provider contains a malformed IP/CIDR range.
    ///
    /// A `.custom` selection whose id is no longer present falls back to the
    /// default built-in provider rather than failing.
    func makeSelectedProvider(resolver: CurrentIPResolver = NetworkIPResolver()) throws -> VPNProvider {
        switch selection {
        case .builtin(let type):
            return type.makeProvider()
        case .custom(let id):
            guard let provider = customProvider(withID: id) else {
                return VPNProviderType.mullvad.makeProvider()
            }
            return try provider.makeProvider(resolver: resolver)
        }
    }
}

/// Loads and saves `AppConfig` to a JSON file in the shared App Group container
/// so the main app and the widget see the same config.
nonisolated enum ConfigStore {
    /// Shared App Group identifier. Both the main app and the widget extension
    /// must enable the "App Groups" capability with this identifier in Xcode.
    static let appGroupIdentifier = "group.dk.montnoir.Egress"

    private static let directoryName = "Egress"
    private static let fileName = "config.json"

    /// The shared container directory (App Group, falling back to Application
    /// Support), creating it if needed. `nil` only if neither is available.
    static var defaultDirectory: URL? {
        let fm = FileManager.default

        let baseDir: URL
        if let groupContainer = fm.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            baseDir = groupContainer
        } else if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            baseDir = appSupport
        } else {
            return nil
        }

        let appDir = baseDir.appendingPathComponent(directoryName, isDirectory: true)
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    static func load() -> AppConfig {
        guard let dir = defaultDirectory else { return .default }
        return load(from: dir)
    }

    /// Loads the config from `config.json` in the given directory, returning the
    /// default if the file is missing or unreadable. Directory is injectable for tests.
    static func load(from directory: URL) -> AppConfig {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    static func save(_ config: AppConfig) {
        guard let dir = defaultDirectory else { return }
        save(config, to: dir)
    }

    /// Writes the config to `config.json` in the given directory. Injectable for tests.
    static func save(_ config: AppConfig, to directory: URL) {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Service class for checking VPN status
class VPNStatusChecker: ObservableObject {
    @Published var currentStatus: VPNStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func checkStatus() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let config = ConfigStore.load()

        do {
            let provider = try config.makeSelectedProvider()
            let status = try await provider.checkStatus()
            await MainActor.run { currentStatus = status }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        await MainActor.run { isLoading = false }
    }

    /// Static method for use in widgets (which can't use @MainActor easily)
    static func checkStatus(using provider: VPNProvider? = nil) async throws -> VPNStatus {
        let config = ConfigStore.load()
        let actualProvider = try provider ?? config.makeSelectedProvider()
        return try await actualProvider.checkStatus()
    }
}

nonisolated enum CustomProviderSaveError: LocalizedError {
    case invalidProvider

    var errorDescription: String? {
        switch self {
        case .invalidProvider:
            return "A custom provider needs a name and at least one valid IP/CIDR range."
        }
    }
}

/// Persists a custom provider into the shared config, creating it or updating the
/// existing one with the same id.
nonisolated enum CustomProviderSaver {
    /// Save into the real shared container (App Group), so the app and widget agree.
    @discardableResult
    static func save(_ provider: CustomProvider) throws -> AppConfig {
        try save(provider, load: ConfigStore.load, persist: ConfigStore.save)
    }

    /// Save into a specific directory. Injectable for tests.
    @discardableResult
    static func save(_ provider: CustomProvider, in directory: URL) throws -> AppConfig {
        try save(
            provider,
            load: { ConfigStore.load(from: directory) },
            persist: { ConfigStore.save($0, to: directory) }
        )
    }

    private static func save(
        _ provider: CustomProvider,
        load: () -> AppConfig,
        persist: (AppConfig) -> Void
    ) throws -> AppConfig {
        guard provider.isValid else { throw CustomProviderSaveError.invalidProvider }
        var config = load()
        config.upsert(provider)
        persist(config)
        return config
    }

    /// Remove a custom provider from the real shared container.
    @discardableResult
    static func remove(id: UUID) -> AppConfig {
        remove(id: id, load: ConfigStore.load, persist: ConfigStore.save)
    }

    /// Remove a custom provider from a specific directory. Injectable for tests.
    @discardableResult
    static func remove(id: UUID, in directory: URL) -> AppConfig {
        remove(
            id: id,
            load: { ConfigStore.load(from: directory) },
            persist: { ConfigStore.save($0, to: directory) }
        )
    }

    private static func remove(
        id: UUID,
        load: () -> AppConfig,
        persist: (AppConfig) -> Void
    ) -> AppConfig {
        var config = load()
        config.removeProvider(id: id)
        persist(config)
        return config
    }
}

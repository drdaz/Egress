//
//  CustomProviderSaver.swift
//  Egress
//
//  Write use-case for custom providers: validate, upsert/remove, stamp the
//  modification time, and persist through `ConfigStore`. App-only (the widget
//  never writes config).
//

import Foundation

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
        config.providersModifiedAt = Date()
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
        config.providersModifiedAt = Date()
        persist(config)
        return config
    }
}

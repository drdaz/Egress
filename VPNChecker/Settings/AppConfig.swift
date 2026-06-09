//
//  AppConfig.swift
//  Egress
//
//  The persisted app-configuration model: the selected provider, the user's custom
//  providers, and the iCloud-synced payload shape, plus the derived queries and
//  mutations over them. Pure value types in the data subsystem, so everything here
//  is `nonisolated` (callable off the main actor — e.g. from the widget extension).
//

import Foundation

/// Persisted app configuration written as JSON in the shared App Group container.
nonisolated struct AppConfig: Codable, Equatable {
    /// User-defined IP-based providers, each selectable in the picker.
    var customProviders: [CustomProvider]
    /// The currently selected provider (built-in or custom).
    var selection: SelectedProvider
    /// When `customProviders` last changed locally. Drives last-write-wins iCloud
    /// sync (the selection itself is per-device and not synced).
    var providersModifiedAt: Date

    static let `default` = AppConfig(customProviders: [], selection: .default)

    init(customProviders: [CustomProvider] = [], selection: SelectedProvider = .default,
         providersModifiedAt: Date = .distantPast) {
        self.customProviders = customProviders
        self.selection = selection
        self.providersModifiedAt = providersModifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case customProviders, selection, providersModifiedAt
    }

    /// Tolerant decoding so a config written before a field existed still loads
    /// (missing keys fall back to defaults instead of failing the whole decode).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customProviders = try container.decodeIfPresent([CustomProvider].self, forKey: .customProviders) ?? []
        selection = try container.decodeIfPresent(SelectedProvider.self, forKey: .selection) ?? .default
        providersModifiedAt = try container.decodeIfPresent(Date.self, forKey: .providersModifiedAt) ?? .distantPast
    }
}

/// The iCloud-synced payload: the custom providers plus when they last changed.
/// Only the providers sync — the selected provider stays per-device.
nonisolated struct SyncedProviders: Codable, Equatable {
    var providers: [CustomProvider]
    var modifiedAt: Date
}

extension AppConfig {
    /// Looks up a custom provider by id.
    nonisolated func customProvider(withID id: UUID) -> CustomProvider? {
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

    /// Replace this config's custom providers with a newer cloud copy (last-write-
    /// wins — the caller decides "newer" via `modifiedAt`). The selection is
    /// per-device so it's kept, unless it pointed at a provider the newer list no
    /// longer contains, in which case it falls back to the default.
    nonisolated func adoptingCustomProviders(_ cloud: SyncedProviders) -> AppConfig {
        var copy = self
        copy.customProviders = cloud.providers
        copy.providersModifiedAt = cloud.modifiedAt
        if case .custom(let id) = copy.selection,
           !cloud.providers.contains(where: { $0.id == id }) {
            copy.selection = .default
        }
        return copy
    }

    /// Display name for the current selection. Falls back to the default built-in's
    /// name when a `.custom` selection references an id that no longer exists.
    nonisolated var selectedProviderName: String {
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
    nonisolated func makeSelectedProvider(resolver: CurrentIPResolver = NetworkIPResolver()) throws -> VPNProvider {
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

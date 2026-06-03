import Foundation
import Combine

/// A selectable entry in the provider picker: a selection value plus its label.
nonisolated struct ProviderPickerItem: Identifiable, Hashable {
    let selection: SelectedProvider
    let label: String
    var id: SelectedProvider { selection }
}

extension AppConfig {
    /// The provider picker's contents: the built-in providers followed by the
    /// user's custom providers, each with its display label.
    var pickerItems: [ProviderPickerItem] {
        VPNProviderType.allCases.map { ProviderPickerItem(selection: .builtin($0), label: $0.displayName) }
            + customProviders.map { ProviderPickerItem(selection: .custom($0.id), label: $0.name) }
    }
}

class ProviderSelection: ObservableObject {
    static let shared = ProviderSelection()

    /// The active selection. Written only via `select(_:)` (which persists) or
    /// `reload(using:)` (which adopts what's already on disk).
    @Published private(set) var selection: SelectedProvider

    private let loadConfig: () -> AppConfig

    /// - Parameter load: config source, injectable for tests. Defaults to the
    ///   shared on-disk store.
    init(load: @escaping () -> AppConfig = ConfigStore.load) {
        self.loadConfig = load
        self.selection = load().selection
    }

    /// User-initiated change: adopt the new selection and persist it.
    func select(_ newValue: SelectedProvider) {
        guard newValue != selection else { return }
        selection = newValue
        var config = ConfigStore.load()
        config.selection = newValue
        ConfigStore.save(config)
    }

    /// Re-read the persisted selection and adopt it if it changed. Lets the UI
    /// pick up config written elsewhere (another scene now; iCloud in a later task)
    /// without restarting. Emits only on an actual change; does not persist, since
    /// the value already came from disk.
    func reload(using load: (() -> AppConfig)? = nil) {
        let persisted = (load ?? loadConfig)().selection
        guard persisted != selection else { return }
        selection = persisted
    }

    /// Display name for the current selection, resolving custom provider names
    /// from the persisted config.
    var selectedProviderName: String {
        switch selection {
        case .builtin(let type):
            return type.displayName
        case .custom:
            return ConfigStore.load().selectedProviderName
        }
    }

    /// The provider picker's contents (built-ins + custom providers), read from
    /// the persisted config.
    var pickerItems: [ProviderPickerItem] {
        ConfigStore.load().pickerItems
    }
}

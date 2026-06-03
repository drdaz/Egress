import Foundation
import Combine

/// A selectable entry in the provider picker: a selection value plus its label.
struct ProviderPickerItem: Identifiable, Hashable {
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

    @Published var selection: SelectedProvider {
        didSet {
            guard oldValue != selection else { return }
            var config = ConfigStore.load()
            config.selection = selection
            ConfigStore.save(config)
        }
    }

    private init() {
        selection = ConfigStore.load().selection
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

import Foundation
import Combine

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
}

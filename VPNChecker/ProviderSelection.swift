import Foundation
import Combine

class ProviderSelection: ObservableObject {
    static let shared = ProviderSelection()

    @Published var providerType: VPNProviderType {
        didSet {
            guard oldValue != providerType else { return }
            var config = ConfigStore.load()
            config.selectedProviderType = providerType
            ConfigStore.save(config)
        }
    }

    private init() {
        providerType = ConfigStore.load().selectedProviderType
    }
}

//
//  VPNStatusChecker.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation
internal import Combine

/// Persisted app configuration written as JSON in Application Support.
struct AppConfig: Codable {
    var selectedProviderType: VPNProviderType

    static let `default` = AppConfig(selectedProviderType: .mullvad)
}

/// Loads and saves `AppConfig` to a JSON file in the shared App Group container
/// so the main app and the widget see the same config.
enum ConfigStore {
    /// Shared App Group identifier. Both the main app and the widget extension
    /// must enable the "App Groups" capability with this identifier in Xcode.
    static let appGroupIdentifier = "group.dk.montnoir.Egress"

    private static let directoryName = "Egress"
    private static let fileName = "config.json"

    private static var fileURL: URL? {
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
        return appDir.appendingPathComponent(fileName)
    }

    static func load() -> AppConfig {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    static func save(_ config: AppConfig) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(config)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Service class for checking VPN status
class VPNStatusChecker: ObservableObject {
    @Published var currentStatus: VPNStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedProviderType: VPNProviderType {
        didSet {
            guard oldValue != selectedProviderType else { return }
            var config = ConfigStore.load()
            config.selectedProviderType = selectedProviderType
            ConfigStore.save(config)
            currentStatus = nil
            errorMessage = nil
        }
    }

    init() {
        self.selectedProviderType = ConfigStore.load().selectedProviderType
    }

    func checkStatus() async {
        await MainActor.run { isLoading = true }
        await MainActor.run { errorMessage = nil }

        let provider = selectedProviderType.makeProvider()

        do {
            let status = try await provider.checkStatus()
            await MainActor.run { currentStatus = status }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        await MainActor.run { isLoading = false }
    }

    /// Static method for use in widgets (which can't use @MainActor easily)
    static func checkStatus(using provider: VPNProvider? = nil) async throws -> VPNStatus {
        let actualProvider = provider ?? ConfigStore.load().selectedProviderType.makeProvider()
        return try await actualProvider.checkStatus()
    }
}

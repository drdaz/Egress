//
//  ConfigStore.swift
//  Egress
//
//  Loads and saves `AppConfig` to a JSON file in the shared App Group container so
//  the main app and the widget see the same config.
//

import Foundation

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

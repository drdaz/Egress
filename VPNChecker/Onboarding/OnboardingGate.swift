import Foundation

/// Per-device record of whether the first-launch onboarding flow has been
/// completed.
///
/// Persisted as a marker file alongside the app's config (the App Group
/// container, falling back to Application Support — see `ConfigStore`). Like the
/// provider selection, this is per-device state: it lives outside the
/// iCloud-synced config, so a new device shows the onboarding on its first
/// launch. Completion is recorded by the marker file's *existence*; its contents
/// are unused.
nonisolated struct OnboardingGate {
    private static let markerFileName = "onboarding-complete"

    private let directory: URL

    /// - Parameter directory: where the marker file lives. Defaults to the shared
    ///   container (`ConfigStore.defaultDirectory`); tests inject a temp dir.
    ///
    /// The default force-unwraps: a nil container means the App Group entitlement
    /// is missing (an incoherent build) or the container has been tampered with —
    /// neither is a recoverable runtime state, so we fail loud at launch rather
    /// than silently degrade.
    init(directory: URL = ConfigStore.defaultDirectory!) {
        self.directory = directory
    }

    private var markerURL: URL {
        directory.appendingPathComponent(Self.markerFileName)
    }

    /// Whether the onboarding screen should be presented on launch.
    var shouldShowOnboarding: Bool {
        !FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Record onboarding as complete so it is not shown again on this device.
    func markComplete() {
        try! Data().write(to: markerURL, options: .atomic)
    }
}

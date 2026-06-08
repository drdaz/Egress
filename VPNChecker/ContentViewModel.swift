//
//  ContentViewModel.swift
//  VPNChecker
//
//  Drives the main screen: runs status checks, tracks when the last one finished,
//  and owns the app/iCloud lifecycle hooks. Kept free of SwiftUI so the logic can
//  be unit-tested with injected doubles instead of the network, WidgetKit, or iCloud.
//

import Foundation
import Combine
import WidgetKit

/// What the main screen should render for the current check.
nonisolated enum VPNCheckState: Equatable {
    case idle
    case loading
    case loaded(VPNStatus)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    /// The app-wide view model. The main window and the macOS menu bar both read
    /// this one instance so they can't show divergent statuses or run duplicate
    /// checks. Tests construct their own instances with injected doubles instead.
    static let shared = ContentViewModel()

    @Published private(set) var state: VPNCheckState = .idle
    @Published private(set) var lastChecked: Date?

    private let runCheck: @MainActor () async -> Result<VPNStatus, Error>
    private let now: @MainActor () -> Date
    private let reloadWidgets: @MainActor () -> Void
    private let startSync: @MainActor () -> Void
    private let reconcileCloud: @MainActor () -> Void

    /// - Parameters are injectable so tests can substitute the network check, the
    ///   clock, widget reloads, and iCloud sync. Defaults wire up the real services.
    init(
        // Default: resolve the selected provider and query its egress status. Only
        // touches the nonisolated checker, so forming this @MainActor closure in the
        // (nonisolated) default-argument context is fine.
        runCheck: @escaping @MainActor () async -> Result<VPNStatus, Error> = {
            do { return .success(try await VPNStatusChecker.checkStatus()) }
            catch { return .failure(error) }
        },
        now: @escaping @MainActor () -> Date = { Date() },
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        startSync: @escaping @MainActor () -> Void = { CloudConfigSync.shared.start() },
        reconcileCloud: @escaping @MainActor () -> Void = { CloudConfigSync.shared.applyCloud() }
    ) {
        self.runCheck = runCheck
        self.now = now
        self.reloadWidgets = reloadWidgets
        self.startSync = startSync
        self.reconcileCloud = reconcileCloud
    }

    /// Distinguishes overlapping `refresh()` calls. `refresh()` is `async`, so the
    /// main actor yields at the network `await` and a second call (e.g. the user
    /// switching providers mid-check) can start before the first returns. Without
    /// this guard, whichever check finishes *last* wins — a slow response for the
    /// previous provider could clobber a fast response for the new one. Tagging each
    /// call and discarding stale results lets the newest call win regardless of
    /// network order, without needing cooperative cancellation (which the underlying
    /// check doesn't support).
    private var checkGeneration = 0

    /// Run a status check, record when it finished, and refresh the widgets.
    /// Results from a superseded call are dropped.
    func refresh() async {
        checkGeneration += 1
        let generation = checkGeneration
        state = .loading

        let result = await runCheck()
        guard generation == checkGeneration else { return }

        switch result {
        case .success(let status): state = .loaded(status)
        case .failure(let error): state = .failed(error.localizedDescription)
        }
        // Stamped/reloaded on both success and failure: we record every completed
        // attempt, and the widget reload is harmless (the extension runs its own check).
        lastChecked = now()
        reloadWidgets()
    }

    /// Whether `startSync()` has already run. Now that `ContentView` observes the
    /// shared view model, its `.task { start() }` fires again for every window that
    /// gets created (e.g. the menu bar's "Open"). iCloud sync is a one-time setup, so
    /// gate it — later appearances just re-check. `CloudConfigSync.start()` is
    /// idempotent today, but making the intent explicit guards against that changing.
    private var syncStarted = false

    /// First appearance: begin iCloud sync, then run an initial check. Subsequent
    /// appearances skip the sync setup and just refresh.
    func start() async {
        if !syncStarted {
            syncStarted = true
            startSync()
        }
        await refresh()
    }

    /// Returning to the foreground: reconcile with iCloud (pull + merge). This also
    /// refreshes the local selection and the widgets via the sync's applied hook.
    func reconcileWithCloud() {
        reconcileCloud()
    }
}

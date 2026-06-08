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
        runCheck: @escaping @MainActor () async -> Result<VPNStatus, Error> = ContentViewModel.defaultCheck,
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

    /// Production check: resolve the selected provider and query its egress status.
    static let defaultCheck: @MainActor () async -> Result<VPNStatus, Error> = {
        do { return .success(try await VPNStatusChecker.checkStatus()) }
        catch { return .failure(error) }
    }

    /// Run a status check, record when it finished, and refresh the widgets.
    func refresh() async {
        state = .loading
        switch await runCheck() {
        case .success(let status): state = .loaded(status)
        case .failure(let error): state = .failed(error.localizedDescription)
        }
        lastChecked = now()
        reloadWidgets()
    }

    /// First appearance: begin iCloud sync, then run an initial check.
    func start() async {
        startSync()
        await refresh()
    }

    /// Returning to the foreground: reconcile with iCloud (pull + merge). This also
    /// refreshes the local selection and the widgets via the sync's applied hook.
    func reconcileWithCloud() {
        reconcileCloud()
    }
}

//
//  ContentViewModelTests.swift
//  EgressTests
//
//  Exercises the main-screen view model with injected doubles so no real network,
//  WidgetKit, or iCloud is touched.
//

import Testing
import Foundation
@testable import Egress

@MainActor
struct ContentViewModelTests {
    /// A fixed status used as the "successful check" result.
    private static let sampleStatus = VPNStatus(
        isConnected: true,
        ipAddress: "1.2.3.4",
        serverLocation: nil,
        country: "Testland",
        city: "Testville",
        organization: "TestOrg",
        providerName: "Mullvad",
        serverName: nil
    )

    private struct CheckFailed: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    /// Builds a view model with inert defaults, overriding only what a test needs.
    private func makeViewModel(
        runCheck: @escaping @MainActor () async -> Result<VPNStatus, Error>,
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 1_000) },
        reloadWidgets: @escaping @MainActor () -> Void = {},
        startSync: @escaping @MainActor () -> Void = {},
        reconcileCloud: @escaping @MainActor () -> Void = {}
    ) -> ContentViewModel {
        ContentViewModel(
            runCheck: runCheck,
            now: now,
            reloadWidgets: reloadWidgets,
            startSync: startSync,
            reconcileCloud: reconcileCloud
        )
    }

    @Test func refreshOnSuccessLoadsStatusStampsTimeAndReloadsWidgets() async {
        let stamp = Date(timeIntervalSince1970: 42)
        var reloaded = false
        let viewModel = makeViewModel(
            runCheck: { .success(Self.sampleStatus) },
            now: { stamp },
            reloadWidgets: { reloaded = true }
        )

        await viewModel.refresh()

        #expect(viewModel.state == .loaded(Self.sampleStatus))
        #expect(viewModel.lastChecked == stamp)
        #expect(reloaded)
    }

    @Test func refreshOnFailureSurfacesMessageStampsTimeAndReloadsWidgets() async {
        let stamp = Date(timeIntervalSince1970: 99)
        var reloaded = false
        let viewModel = makeViewModel(
            runCheck: { .failure(CheckFailed()) },
            now: { stamp },
            reloadWidgets: { reloaded = true }
        )

        await viewModel.refresh()

        #expect(viewModel.state == .failed("boom"))
        #expect(viewModel.lastChecked == stamp)
        #expect(reloaded)
    }

    @Test func startBeginsSyncThenRefreshes() async {
        var syncStarted = false
        let viewModel = makeViewModel(
            runCheck: { .success(Self.sampleStatus) },
            startSync: { syncStarted = true }
        )

        await viewModel.start()

        #expect(syncStarted)
        #expect(viewModel.state == .loaded(Self.sampleStatus))
        #expect(viewModel.lastChecked != nil)
    }

    @Test func reconcileWithCloudTriggersReconciliation() {
        var reconciled = false
        let viewModel = makeViewModel(
            runCheck: { .success(Self.sampleStatus) },
            reconcileCloud: { reconciled = true }
        )

        viewModel.reconcileWithCloud()

        #expect(reconciled)
    }

    @Test func isLoadingReflectsLoadingState() {
        #expect(VPNCheckState.loading.isLoading)
        #expect(!VPNCheckState.idle.isLoading)
        #expect(!VPNCheckState.loaded(Self.sampleStatus).isLoading)
        #expect(!VPNCheckState.failed("x").isLoading)
    }
}

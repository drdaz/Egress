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
    /// Builds a status with a distinguishing IP (the rest is fixed boilerplate).
    private static func makeStatus(ip: String) -> VPNStatus {
        VPNStatus(
            isConnected: true,
            ipAddress: ip,
            serverLocation: nil,
            country: "Testland",
            city: "Testville",
            organization: "TestOrg",
            providerName: "Mullvad",
            serverName: nil
        )
    }

    /// A fixed status used as the "successful check" result.
    private static let sampleStatus = makeStatus(ip: "1.2.3.4")

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
        var callOrder: [String] = []
        let viewModel = makeViewModel(
            runCheck: { callOrder.append("check"); return .success(Self.sampleStatus) },
            startSync: { callOrder.append("sync") }
        )

        await viewModel.start()

        #expect(callOrder == ["sync", "check"])
    }

    @Test func staleCheckDoesNotOverwriteNewerResult() async {
        let slow = Self.makeStatus(ip: "9.9.9.9")
        let fast = Self.makeStatus(ip: "1.1.1.1")

        // The first (slow) check parks on a gate; the second (fast) check returns
        // immediately. Releasing the gate afterwards must not let the stale first
        // result overwrite the newer second one.
        var gate: CheckedContinuation<Void, Never>?
        var callCount = 0
        let viewModel = makeViewModel(runCheck: {
            callCount += 1
            if callCount == 1 {
                await withCheckedContinuation { gate = $0 }
                return .success(slow)
            }
            return .success(fast)
        })

        async let firstCall: Void = viewModel.refresh()
        while gate == nil { await Task.yield() }   // let the slow call park
        #expect(viewModel.state == .loading)       // state is .loading while a check is in flight
        await viewModel.refresh()                  // newer call wins
        #expect(viewModel.state == .loaded(fast))

        gate?.resume()                             // slow call now finishes...
        await firstCall
        #expect(viewModel.state == .loaded(fast))  // ...but its result is discarded
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

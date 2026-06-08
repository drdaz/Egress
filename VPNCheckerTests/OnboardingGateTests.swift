//
//  OnboardingGateTests.swift
//  EgressTests
//
//  The per-device first-launch onboarding flag: the presentation decision and
//  marking it complete, exercised against a temp directory so the real shared
//  container is never touched.
//

import Foundation
import Testing
@testable import Egress

struct OnboardingGateTests {

    @Test func showsOnboardingWhenMarkerAbsent() throws {
        try withTempDirectory { dir in
            let gate = OnboardingGate(directory: dir)
            #expect(gate.shouldShowOnboarding)
        }
    }

    @Test func markCompleteSuppressesSubsequentShow() throws {
        try withTempDirectory { dir in
            OnboardingGate(directory: dir).markComplete()
            // A fresh gate over the same directory (as a relaunch would see) must not show.
            #expect(!OnboardingGate(directory: dir).shouldShowOnboarding)
        }
    }

    @Test func markCompleteWritesTheMarkerFile() throws {
        try withTempDirectory { dir in
            OnboardingGate(directory: dir).markComplete()
            let marker = dir.appendingPathComponent("onboarding-complete")
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }
    }
}

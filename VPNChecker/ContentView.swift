//
//  ContentView.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @ObservedObject private var providerSelection = ProviderSelection.shared
    @State private var showingSettings = false
    @State private var showingOnboarding: Bool
    @Environment(\.scenePhase) private var scenePhase

    private let onboardingGate: OnboardingGate

    init() {
        // Construct the gate once (each `OnboardingGate()` resolves the container
        // dir) and seed the sheet state before first render, so a first-launch
        // user doesn't briefly see the main content before onboarding appears.
        let gate = OnboardingGate()
        onboardingGate = gate
        _showingOnboarding = State(initialValue: gate.shouldShowOnboarding)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                StatusContentView(
                    state: viewModel.state,
                    providerName: providerSelection.selectedProviderName
                )

                CheckStatusButton(isLoading: viewModel.state.isLoading) {
                    Task { await viewModel.refresh() }
                }

                if let lastChecked = viewModel.lastChecked {
                    LastCheckedLabel(date: lastChecked)
                }
            }
            .padding()
            .navigationTitle("Egress")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await viewModel.start() }
            .onChange(of: providerSelection.selection) { _, _ in
                Task { await viewModel.refresh() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.reconcileWithCloud() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    #if os(macOS)
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    #else
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    #endif
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
            }
            #endif
        }
        // First-launch onboarding, presented over the main view on both platforms.
        // Attached at the NavigationStack level (a different tree position than the
        // iOS settings sheet above) so the two sheets don't conflict.
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView {
                onboardingGate.markComplete()
                showingOnboarding = false
            }
        }
    }
}

/// The primary "Check Status" action button.
struct CheckStatusButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Check Status", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
    }
}

/// Relative "last checked" caption shown under the action button.
struct LastCheckedLabel: View {
    let date: Date

    var body: some View {
        Text("Last checked: \(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var checker = VPNStatusChecker()
    @ObservedObject private var providerSelection = ProviderSelection.shared
    @State private var lastChecked: Date?
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if checker.isLoading {
                    ProgressView("Checking \(providerSelection.selectedProviderName) status...")
                } else if let status = checker.currentStatus {
                    VPNStatusView(
                        status: status,
                        selectedProviderName: providerSelection.selectedProviderName
                    )
                } else if let error = checker.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)
                        Text("Error checking \(providerSelection.selectedProviderName)")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: 50))
                            .foregroundStyle(.gray)
                        Text("Check your \(providerSelection.selectedProviderName) status")
                            .font(.headline)
                    }
                }

                Button {
                    Task {
                        await checker.checkStatus()
                        lastChecked = Date()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                } label: {
                    Label("Check Status", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(checker.isLoading)

                if let lastChecked {
                    Text("Last checked: \(lastChecked, format: .relative(presentation: .named, unitsStyle: .abbreviated))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Egress")
            .navigationSubtitle("VPN Checker")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                CloudConfigSync.shared.start()
                await checker.checkStatus()
                lastChecked = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: providerSelection.selection) { _, _ in
                Task {
                    await checker.checkStatus()
                    lastChecked = Date()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Pick up config changed elsewhere (other scene now, iCloud later).
                if phase == .active { providerSelection.reload() }
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
    }
}

struct VPNStatusView: View {
    let status: VPNStatus
    let selectedProviderName: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: status.isConnected ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(status.isConnected ? .green : .red)

            Text(status.isConnected ? "Connected" : "Not connected")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "Provider", value: selectedProviderName)

                InfoRow(label: "IP Address", value: status.ipAddress)

                if let server = status.serverName {
                    InfoRow(label: "Server", value: server)
                }

                InfoRow(label: "Location", value: status.locationDescription)

                if let organization = status.organization {
                    InfoRow(label: "Organization", value: organization)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ContentView()
}

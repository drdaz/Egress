//
//  StatusContentView.swift
//  VPNChecker
//
//  The status area of the main screen: picks the right presentation for the
//  current check state (loading / connected detail / error / idle prompt).
//

import SwiftUI

/// Renders the main status area for the current check state.
struct StatusContentView: View {
    let state: VPNCheckState
    let providerName: String

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Checking \(providerName) status...")
        case .loaded(let status):
            VPNStatusView(status: status, selectedProviderName: providerName)
        case .failed(let message):
            StatusMessageView(
                systemImage: "exclamationmark.triangle",
                tint: .orange,
                title: "Error checking \(providerName)",
                message: message
            )
        case .idle:
            StatusMessageView(
                systemImage: "network",
                tint: .gray,
                title: "Check your \(providerName) status",
                message: nil
            )
        }
    }
}

/// A centred icon + headline (+ optional detail), shared by the error and idle
/// states which differ only in their symbol, tint, and copy.
struct StatusMessageView: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// The connected/disconnected detail card shown once a status has loaded.
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

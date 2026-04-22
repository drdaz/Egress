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
    @State private var lastChecked: Date?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if checker.isLoading {
                    ProgressView("Checking VPN status...")
                } else if let status = checker.currentStatus {
                    VPNStatusView(status: status)
                } else if let error = checker.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)
                        Text("Error")
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
                        Text("Check your VPN status")
                            .font(.headline)
                    }
                }
                
                Button {
                    Task {
                        await checker.checkStatus()
                        lastChecked = Date()
                        // Refresh widgets after checking status
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                } label: {
                    Label("Check Status", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
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
            .navigationTitle("VPN Checker")
            .task {
                await checker.checkStatus()
                lastChecked = Date()
                // Refresh widgets when app appears
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

struct VPNStatusView: View {
    let status: VPNStatus
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: status.isConnected ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(status.isConnected ? .green : .red)
            
            Text(status.isConnected ? "Connected" : "Not Connected")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
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

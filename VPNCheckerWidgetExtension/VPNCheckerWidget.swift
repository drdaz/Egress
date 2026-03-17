//
//  VPNCheckerWidget.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import WidgetKit
import SwiftUI

struct VPNCheckerWidget: Widget {
    let kind: String = "VPNCheckerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VPNStatusProvider()) { entry in
            VPNWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("VPN Status")
        .description("Check if you're connected to your VPN")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Provider

struct VPNStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> VPNStatusEntry {
        VPNStatusEntry(
            date: Date(),
            status: VPNStatus(
                isConnected: true,
                ipAddress: "10.0.0.1",
                serverLocation: "wireguard",
                country: "Sweden",
                city: "Stockholm",
                organization: "Mullvad VPN",
                providerName: "Mullvad",
                serverName: "se-sto-wg-001"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (VPNStatusEntry) -> ()) {
        Task {
            do {
                let status = try await VPNStatusChecker.checkStatus()
                let entry = VPNStatusEntry(date: Date(), status: status)
                completion(entry)
            } catch {
                print("❌ Widget snapshot error: \(error)")
                let entry = VPNStatusEntry(date: Date(), status: nil, error: formatError(error))
                completion(entry)
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VPNStatusEntry>) -> ()) {
        Task {
            do {
                let status = try await VPNStatusChecker.checkStatus()
                let entry = VPNStatusEntry(date: Date(), status: status)
                
                // Refresh every 15 minutes
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                print("❌ Widget timeline error: \(error)")
                let entry = VPNStatusEntry(date: Date(), status: nil, error: formatError(error))
                
                // Retry in 5 minutes on error
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            }
        }
    }
    
    private func formatError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection"
            case .cannotConnectToHost:
                return "Cannot reach VPN API"
            case .networkConnectionLost:
                return "Network connection lost"
            case .timedOut:
                return "Request timed out"
            default:
                return "Network error: \(urlError.code.rawValue)"
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Timeline Entry

struct VPNStatusEntry: TimelineEntry {
    let date: Date
    let status: VPNStatus?
    var error: String?
}

// MARK: - Widget Views

struct VPNWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: VPNStatusEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallVPNWidgetView(entry: entry)
        case .systemMedium:
            MediumVPNWidgetView(entry: entry)
        default:
            SmallVPNWidgetView(entry: entry)
        }
    }
}

struct SmallVPNWidgetView: View {
    let entry: VPNStatusEntry
    
    var body: some View {
        if let error = entry.error {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let status = entry.status {
            VStack(spacing: 8) {
                Image(systemName: status.isConnected ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(status.isConnected ? .green : .red)
                
                Text(status.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                if status.isConnected {
                    Text(status.providerName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let server = status.serverName {
                        Text(server)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if let country = status.country {
                        Text(country)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.largeTitle)
                    .foregroundStyle(.gray)
                Text("Loading...")
                    .font(.caption)
            }
        }
    }
}

struct MediumVPNWidgetView: View {
    let entry: VPNStatusEntry
    
    var body: some View {
        if let error = entry.error {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error Checking Status")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding()
        } else if let status = entry.status {
            HStack(spacing: 16) {
                Image(systemName: status.isConnected ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(status.isConnected ? .green : .red)
                
                VStack(alignment: .leading, spacing: 6) {
                    if status.isConnected {
                        Text("Connected to \(status.providerName)")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        if let server = status.serverName {
                            Text("Server: \(server)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(status.locationDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("VPN Disconnected")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("IP: \(status.ipAddress)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Updated \(entry.date.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
            .padding()
        } else {
            HStack(spacing: 16) {
                ProgressView()
                Text("Checking VPN status...")
                    .font(.subheadline)
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    VPNCheckerWidget()
} timeline: {
    VPNStatusEntry(
        date: .now,
        status: VPNStatus(
            isConnected: true,
            ipAddress: "10.0.0.1",
            serverLocation: "wireguard",
            country: "Sweden",
            city: "Stockholm",
            organization: "Mullvad VPN",
            providerName: "Mullvad",
            serverName: "se-sto-wg-001"
        )
    )
    VPNStatusEntry(
        date: .now,
        status: VPNStatus(
            isConnected: false,
            ipAddress: "203.0.113.1",
            serverLocation: nil,
            country: "United States",
            city: "New York",
            organization: "ISP Corp",
            providerName: "None",
            serverName: nil
        )
    )
}

#Preview(as: .systemMedium) {
    VPNCheckerWidget()
} timeline: {
    VPNStatusEntry(
        date: .now,
        status: VPNStatus(
            isConnected: true,
            ipAddress: "10.0.0.1",
            serverLocation: "wireguard",
            country: "Sweden",
            city: "Stockholm",
            organization: "Mullvad VPN",
            providerName: "Mullvad",
            serverName: "se-sto-wg-001"
        )
    )
}

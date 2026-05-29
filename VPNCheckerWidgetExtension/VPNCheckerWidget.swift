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
        .configurationDisplayName("Egress")
        .description("Check if you're connected to your VPN")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Provider

struct VPNStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> VPNStatusEntry {
        return VPNStatusEntry(
            date: Date(),
            status: nil,
            selectedProviderName: ""
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (VPNStatusEntry) -> ()) {
        let selectedName = ConfigStore.load().selectedProviderType.displayName
        Task {
            do {
                let status = try await VPNStatusChecker.checkStatus()
                let entry = VPNStatusEntry(date: Date(), status: status, selectedProviderName: selectedName)
                completion(entry)
            } catch {
                let entry = VPNStatusEntry(date: Date(), status: nil, selectedProviderName: selectedName, error: formatError(error))
                completion(entry)
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VPNStatusEntry>) -> ()) {
        let selectedName = ConfigStore.load().selectedProviderType.displayName
        Task {
            do {
                let status = try await VPNStatusChecker.checkStatus()
                let entry = VPNStatusEntry(date: Date(), status: status, selectedProviderName: selectedName)

                // Refresh every 15 minutes
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                let entry = VPNStatusEntry(date: Date(), status: nil, selectedProviderName: selectedName, error: formatError(error))

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
    let selectedProviderName: String
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
        widgetContent
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        if entry.error != nil {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(entry.selectedProviderName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Error")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let status = entry.status {
            VStack(spacing: 8) {
                Image(systemName: status.isConnected ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(status.isConnected ? .green : .red)

                Text(entry.selectedProviderName)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(status.isConnected ? "Connected" : "Not connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if status.isConnected {
                    if let server = status.serverName {
                        Text(server)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if let country = status.country {
                        Text(country)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(status.ipAddress)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                    Text("Error checking \(entry.selectedProviderName)")
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
                        Text("Connected to \(entry.selectedProviderName)")
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
                        Text("Not connected to \(entry.selectedProviderName)")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("IP: \(status.ipAddress)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        } else {
            HStack(spacing: 16) {
                ProgressView()
                Text("Checking \(entry.selectedProviderName) status...")
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
        ),
        selectedProviderName: "Mullvad"
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
        ),
        selectedProviderName: "AirVPN"
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
        ),
        selectedProviderName: "Mullvad"
    )
}

//
//  VPNCheckerAppIntents.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import AppIntents
import Foundation

/// App Intent for checking VPN status via Siri or Shortcuts
struct CheckVPNStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check VPN Status"
    static var description = IntentDescription("Checks if you're currently connected to your VPN")
    
    // Don't open the app, but request foreground mode for network access
    static var openAppWhenRun: Bool = false
    
    // Request foreground mode to get network access without showing UI
    static var supportedModes: IntentModes = [.foreground(.immediate)]
    
    static var isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let status = try await VPNStatusChecker.checkStatus()
            
            if status.isConnected {
                return .result(
                    dialog: IntentDialog("You are connected to VPN in \(status.locationDescription)")
                )
            } else {
                return .result(
                    dialog: IntentDialog("You are not connected to VPN. Your IP is \(status.ipAddress)")
                )
            }
        } catch {
            return .result(
                dialog: IntentDialog("Failed to check VPN status: \(error.localizedDescription)")
            )
        }
    }
}

/// App Shortcuts configuration
struct VPNCheckerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckVPNStatusIntent(),
            phrases: [
                "Check my VPN in \(.applicationName)",
                "Am I connected to VPN in \(.applicationName)",
                "Check VPN status in \(.applicationName)"
            ],
            shortTitle: "Check VPN",
            systemImageName: "network.badge.shield.half.filled"
        )
    }
}

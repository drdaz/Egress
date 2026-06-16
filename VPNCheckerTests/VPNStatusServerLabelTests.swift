//
//  VPNStatusServerLabelTests.swift
//  EgressTests
//
//  Covers VPNStatus.serverOrIP — the widget's secondary-line fallback.
//

import Foundation
import Testing
@testable import Egress

struct VPNStatusServerLabelTests {

    private func status(serverName: String?, ipAddress: String, isConnected: Bool = true) -> VPNStatus {
        VPNStatus(
            isConnected: isConnected,
            ipAddress: ipAddress,
            serverLocation: nil,
            country: nil,
            city: nil,
            organization: nil,
            providerName: "Test",
            serverName: serverName
        )
    }

    @Test func usesServerNameWhenPresent() {
        #expect(status(serverName: "Lupus", ipAddress: "1.2.3.4").serverOrIP == "Lupus")
    }

    @Test func fallsBackToIPWhenNoServerName() {
        #expect(status(serverName: nil, ipAddress: "203.0.113.7").serverOrIP == "203.0.113.7")
    }

    @Test func fallsBackToIPWhenServerNameEmpty() {
        #expect(status(serverName: "", ipAddress: "203.0.113.7").serverOrIP == "203.0.113.7")
    }

    @Test func fallsBackToIPWhenServerNameBlank() {
        #expect(status(serverName: "   ", ipAddress: "203.0.113.7").serverOrIP == "203.0.113.7")
    }

    /// The fallback is independent of connection state — a not-connected status
    /// (no server name) still surfaces the egress IP rather than a blank line.
    @Test func fallsBackToIPRegardlessOfConnectedState() {
        #expect(status(serverName: nil, ipAddress: "203.0.113.7", isConnected: false).serverOrIP == "203.0.113.7")
    }
}

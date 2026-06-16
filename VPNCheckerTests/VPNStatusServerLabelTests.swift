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

    /// serverOrIP is connection-agnostic by design — a pure formatting helper, not
    /// a connection-state decision (gating it on isConnected was deliberately
    /// declined). With no server name it returns the IP whether connected or not...
    @Test func fallsBackToIPWhenDisconnectedAndNoServerName() {
        #expect(status(serverName: nil, ipAddress: "203.0.113.7", isConnected: false).serverOrIP == "203.0.113.7")
    }

    /// ...and a (e.g. stale) server name still takes precedence even when
    /// disconnected, rather than reverting to the IP. The view, not this helper,
    /// is responsible for connection-state presentation.
    @Test func serverNameTakesPrecedenceEvenWhenDisconnected() {
        #expect(status(serverName: "se-sto-wg-001", ipAddress: "203.0.113.7", isConnected: false).serverOrIP == "se-sto-wg-001")
    }
}

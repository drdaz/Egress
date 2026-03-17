//
//  VPNCheckerApp.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import SwiftUI

@main
struct VPNCheckerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            ContentView()
        }
        #else
        // macOS: Menu bar app with optional window
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        Settings {
            SettingsView()
        }
        #endif
    }
}
#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var checker = VPNStatusChecker()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "VPN Status")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        
        // Setup menu
        setupMenu()
        
        // Start monitoring
        Task {
            await updateMenuBarIcon()
        }
        
        // Update every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.updateMenuBarIcon() }
        }
    }
    
    @objc func statusBarButtonClicked() {
        guard let button = statusItem?.button else { return }
        
        if let menu = statusItem?.menu {
            statusItem?.menu = nil
            // Toggle behavior: click shows menu
        } else {
            setupMenu()
            statusItem?.button?.performClick(nil)
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 999 // Use tag to find and update this item
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshStatus), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Window", action: #selector(openWindow), keyEquivalent: "o"))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        // Update status immediately
        Task {
            await updateMenuStatus()
        }
    }
    
    @objc func refreshStatus() {
        Task {
            await checker.checkStatus()
            await updateMenuStatus()
            await updateMenuBarIcon()
        }
    }
    
    @objc func openWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func updateMenuBarIcon() async {
        await checker.checkStatus()
        
        let imageName: String
        if let status = checker.currentStatus {
            imageName = status.isConnected ? "lock.shield.fill" : "lock.open.fill"
        } else {
            imageName = "lock.shield"
        }
        
        await MainActor.run {
            statusItem?.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "VPN Status")
        }
        
        await updateMenuStatus()
    }
    
    private func updateMenuStatus() async {
        await MainActor.run {
            guard let menu = statusItem?.menu else { return }
            
            if let statusItem = menu.items.first(where: { $0.tag == 999 }) {
                if let status = checker.currentStatus {
                    let icon = status.isConnected ? "✅" : "❌"
                    let location = status.isConnected ? status.locationDescription : "Not Connected"
                    statusItem.title = "\(icon) \(location)"
                } else if let error = checker.errorMessage {
                    statusItem.title = "⚠️ \(error)"
                } else {
                    statusItem.title = "Checking..."
                }
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("VPN Checker Settings")
                .font(.title)
            
            Text("Status bar icon shows your VPN connection status")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
#endif


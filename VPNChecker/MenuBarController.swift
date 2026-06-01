#if os(macOS)
import AppKit
import SwiftUI
import WidgetKit

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var checker = VPNStatusChecker()
    private var timer: Timer?

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "VPN Status")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        setupMenu()

        Task { await updateMenuBarIcon() }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.updateMenuBarIcon() }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerChanged),
            name: .vpnProviderChanged,
            object: nil
        )
    }

    @objc private func providerChanged() {
        Task { await updateMenuBarIcon() }
    }

    @objc private func statusBarButtonClicked() {
        guard (statusItem?.button) != nil else { return }

        if (statusItem?.menu) != nil {
            statusItem?.menu = nil
        } else {
            setupMenu()
            statusItem?.button?.performClick(nil)
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 999
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openItem = NSMenuItem(title: "Open", action: #selector(openWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu

        Task { await updateMenuStatus() }
    }

    @objc private func refreshStatus() {
        Task {
            await checker.checkStatus()
            await updateMenuStatus()
            await updateMenuBarIcon()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @objc private func openWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = NSApplication.shared.windows.first(where: {
            $0.canBecomeKey && $0.isVisible && !$0.isKind(of: NSPanel.self)
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        createNewWindow()
    }

    private func createNewWindow() {
        let contentView = ContentView()
            .frame(width: 400, height: 500)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Egress"
        window.setContentSize(NSSize(width: 400, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.minSize = NSSize(width: 400, height: 500)
        window.maxSize = NSSize(width: 400, height: 500)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
    }

    private func updateMenuBarIcon() async {
        await checker.checkStatus()

        let imageName: String
        let tooltipText: String

        if let status = checker.currentStatus {
            imageName = status.isConnected ? "lock.shield.fill" : "lock.open.fill"
            tooltipText = status.multilineDescription
        } else if let error = checker.errorMessage {
            imageName = "lock.shield"
            tooltipText = "Error: \(error)"
        } else {
            imageName = "lock.shield"
            tooltipText = "VPN Status"
        }

        await MainActor.run {
            statusItem?.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "VPN Status")
            statusItem?.button?.toolTip = tooltipText
        }

        await updateMenuStatus()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateMenuStatus() async {
        await MainActor.run {
            guard let menu = statusItem?.menu else { return }

            if let statusItem = menu.items.first(where: { $0.tag == 999 }) {
                if let status = checker.currentStatus {
                    let icon = status.isConnected ? "✅" : "❌"
                    statusItem.title = "\(icon) \(status.singleLineDescription)"
                } else if let error = checker.errorMessage {
                    statusItem.title = "⚠️ \(error)"
                } else {
                    statusItem.title = "Checking..."
                }
            }
        }
    }
}
#endif

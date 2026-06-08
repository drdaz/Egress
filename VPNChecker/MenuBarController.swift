#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    // Shared with the main window so the menu bar and window can't show different
    // statuses or run duplicate checks.
    private let viewModel = ContentViewModel.shared
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "VPN Status")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        setupMenu()

        // Re-render the icon/tooltip/menu whenever the shared check state changes —
        // including the initial value, which paints the "Checking…" placeholder.
        // `state` is @MainActor-mutated, so the publisher fires on the main actor and
        // we can render synchronously (matching setupMenu's direct render call).
        viewModel.$state
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)

        // Re-check when the user switches providers, even while the window is closed.
        // When it's open ContentView also refreshes; the newest check wins regardless.
        ProviderSelection.shared.$selection
            .dropFirst()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Initial check, then poll so a status change made outside the app shows up.
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
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

        // Paint the freshly built menu with the current state.
        render(viewModel.state)
    }

    @objc private func refreshStatus() {
        refresh()
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

    /// Kick off a shared check. `ContentViewModel.refresh()` already reloads the
    /// widgets, so there's nothing extra to do here.
    private func refresh() {
        Task { await viewModel.refresh() }
    }

    /// Map the shared check state onto the status item's icon/tooltip and the menu's
    /// status line. `.loaded` shows the status, `.failed` the error, and
    /// `.loading`/`.idle` the neutral "Checking…" placeholder.
    private func render(_ state: VPNCheckState) {
        let imageName: String
        let tooltip: String
        let menuTitle: String

        switch state {
        case .loaded(let status):
            imageName = status.isConnected ? "lock.shield.fill" : "lock.open.fill"
            tooltip = status.multilineDescription
            let icon = status.isConnected ? "✅" : "❌"
            menuTitle = "\(icon) \(status.singleLineDescription)"
        case .failed(let message):
            imageName = "lock.shield"
            tooltip = "Error: \(message)"
            menuTitle = "⚠️ \(message)"
        case .loading, .idle:
            imageName = "lock.shield"
            tooltip = "VPN Status"
            menuTitle = "Checking..."
        }

        statusItem?.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "VPN Status")
        statusItem?.button?.toolTip = tooltip

        if let menu = statusItem?.menu,
           let statusMenuItem = menu.items.first(where: { $0.tag == 999 }) {
            statusMenuItem.title = menuTitle
        }
    }
}
#endif

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
        Window("Egress", id: "main") {
            ContentView()
                .frame(minWidth: 400, idealWidth: 400, maxWidth: 400,
                       minHeight: 500, idealHeight: 500, maxHeight: 500)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 500)
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
        #endif
    }
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.start()
    }
}
#endif

# Menu Bar App Configuration

Your VPN Checker can run as a menu bar app (status bar app) instead of showing in the Dock. This is perfect for background monitoring!

## Current Setup: Hybrid Mode

I've updated `VPNCheckerApp.swift` to add menu bar support while keeping the dock icon. This gives you:

- ✅ Menu bar icon showing VPN status
- ✅ Click icon to see status and refresh
- ✅ App window still available
- ✅ Works on iOS (shows normal app) and macOS (adds menu bar)

**The menu bar icon changes based on your connection:**
- 🔒 Filled lock = Connected
- 🔓 Open lock = Disconnected  
- 🔒 Gray lock = Checking/Error

## Option 1: Hide from Dock (Menu Bar Only) ⭐ RECOMMENDED

To make it **only** appear in the menu bar (no dock icon), add this to your **Info.plist**:

### Steps:

1. Select your **main app target** in Xcode
2. Go to the **Info** tab
3. Hover over any key and click the **+** button
4. Add new key: **Application is agent (UIElement)** or type `LSUIElement`
5. Set the value to **YES** (Boolean)

This tells macOS to hide the app from the Dock and keep it menu bar only.

### Info.plist XML:

If you prefer to edit the raw plist:

```xml
<key>LSUIElement</key>
<true/>
```

### Result:
- ✅ No dock icon
- ✅ Menu bar icon always visible
- ✅ Widget works independently
- ✅ Click menu bar icon to check status
- ✅ Quit from menu bar menu

## Option 2: Menu Bar Only with Popover (Alternative)

If you want a fancier UI, use `MenuBarApp.swift` instead:

1. **Remove** `@main` from `VPNCheckerApp.swift`
2. **Add** `@main` to `MenuBarApp.swift`
3. Add `LSUIElement = YES` to Info.plist

This gives you:
- ✅ Click icon shows popover with full status
- ✅ Nicer UI in a floating window
- ✅ Auto-updates every 30 seconds
- ✅ Quit button in popover

## Option 3: Keep Both (Current Setup)

Want the dock icon AND menu bar? Keep it as-is! You get both:
- Menu bar icon for quick glances
- Full app window for details
- Both update automatically

## Customization

### Change Update Frequency

In `VPNCheckerApp.swift`, find this line:

```swift
Timer.scheduledTimer(withTimeInterval: 30, repeats: true)
```

Change `30` to your preferred seconds (e.g., `60` for 1 minute, `300` for 5 minutes).

### Change Menu Bar Icon

Customize the icons in the `updateMenuBarIcon()` function:

```swift
let imageName: String
if let status = checker.currentStatus {
    // Change these icon names:
    imageName = status.isConnected ? "lock.shield.fill" : "lock.open.fill"
    // Try: "checkmark.circle.fill" / "xmark.circle.fill"
    // Or: "wifi" / "wifi.slash"
    // Or: "network" / "network.slash"
} else {
    imageName = "lock.shield"
}
```

### Add Click-to-Copy IP

Add this to the menu setup:

```swift
if let status = checker.currentStatus {
    let ipItem = NSMenuItem(
        title: "Copy IP: \(status.ipAddress)",
        action: #selector(copyIP),
        keyEquivalent: "c"
    )
    menu.addItem(ipItem)
}

@objc func copyIP() {
    if let ip = checker.currentStatus?.ipAddress {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }
}
```

## Comparison

| Feature | Default App | Hybrid (Current) | Menu Bar Only |
|---------|-------------|------------------|---------------|
| Dock Icon | ✅ | ✅ | ❌ |
| Menu Bar Icon | ❌ | ✅ | ✅ |
| Full Window | ✅ | ✅ | Optional |
| Auto-Update | ❌ | ✅ | ✅ |
| Widget Works | ✅ | ✅ | ✅ |
| Background Running | ❌ | ✅ | ✅ |

## Recommended Setup for VPN Checker

**Menu Bar Only** is ideal because:

1. ✅ Always visible but unobtrusive
2. ✅ Glanceable status at a glance (lock icon changes color)
3. ✅ Doesn't clutter your Dock
4. ✅ Widget still works perfectly
5. ✅ Similar to how actual VPN apps work (Mullvad, NordVPN, etc.)

## How to Switch

### To Menu Bar Only:

1. Keep the updated `VPNCheckerApp.swift` (or use `MenuBarApp.swift`)
2. Add `LSUIElement = YES` to Info.plist
3. Clean build (⇧⌘K) and run
4. App appears only in menu bar

### To Revert to Normal App:

1. Remove `LSUIElement` key from Info.plist
2. Clean build and run
3. App appears in Dock again

## Widget Independence

Good news! **The widget works regardless of your choice!**

- Widgets are independent processes
- They don't require the main app to be running
- Adding `LSUIElement` doesn't affect widget functionality
- Widget updates on its own timeline (every 15 minutes)

So you can:
- Hide the app from Dock with `LSUIElement`
- Keep the menu bar icon for manual checks
- Let the widget update automatically
- Best of both worlds! 🎉

## iOS Behavior

On iOS, all this menu bar code is ignored:
- Shows normal app with ContentView
- No menu bar (iOS doesn't have one)
- Widget works as normal
- Uses `#if os(macOS)` to conditionally compile

## Launch at Login

Want it to start automatically? Add "Launch at Login" capability:

1. Main app target → **Signing & Capabilities**
2. Click **+** → **Login Items**
3. Users can enable in System Settings → Login Items

Or add a menu item:

```swift
import ServiceManagement

let launchItem = NSMenuItem(
    title: "Launch at Login",
    action: #selector(toggleLaunchAtLogin),
    keyEquivalent: ""
)
launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
menu.addItem(launchItem)

@objc func toggleLaunchAtLogin() {
    let service = SMAppService.mainApp
    do {
        if service.status == .enabled {
            try service.unregister()
        } else {
            try service.register()
        }
    } catch {
        print("Failed to toggle launch at login: \(error)")
    }
}
```

## Summary

**Quick Setup for Menu Bar Only:**

1. ✅ Already done: `VPNCheckerApp.swift` has menu bar code
2. ➕ Add: `LSUIElement = YES` to Info.plist
3. 🏗️ Clean build and run
4. 🎉 Enjoy your menu bar VPN checker!

The icon will automatically update based on your VPN status, and you can click it anytime to refresh or quit.

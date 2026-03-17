# Project Setup Guide

## What I've Built For You

I've created a complete VPN checker system with:

### ✅ Core Architecture
1. **VPNProvider.swift** - Protocol-based system for any VPN provider
2. **MullvadProvider.swift** - Full Mullvad API integration
3. **VPNStatusChecker.swift** - Service for checking VPN status
4. **ContentView.swift** - Beautiful main app UI

### ✅ Widget System
5. **VPNCheckerWidget.swift** - iOS/macOS widgets (small & medium)
6. **VPNCheckerWidgetBundle.swift** - Widget entry point

### ✅ Bonus Features
7. **VPNCheckerAppIntents.swift** - Siri shortcuts & Shortcuts app support
8. **ExampleProviders.swift** - Templates for adding more VPN providers

## Next Steps to Get Running

### Step 1: Create Widget Extension Target

You need to add a Widget Extension to your Xcode project:

1. **File > New > Target...**
2. Select **Widget Extension** (under iOS or Multiplatform)
3. Product Name: `VPNCheckerWidgetExtension`
4. **UNCHECK** "Include Configuration Intent"
5. Click **Finish**
6. When asked to activate scheme, click **Activate**

### Step 2: Configure File Membership

**Delete** the default widget files Xcode created:
- Delete `VPNCheckerWidgetExtension.swift` (we have better files)
- Delete `VPNCheckerWidgetExtensionBundle.swift` (we have better files)

**Add files to BOTH targets** (Main App + Widget Extension):
- ✅ VPNProvider.swift
- ✅ MullvadProvider.swift  
- ✅ VPNStatusChecker.swift

**Add files to Widget Extension target ONLY**:
- ✅ VPNCheckerWidget.swift
- ✅ VPNCheckerWidgetBundle.swift

**Add files to Main App target ONLY**:
- ✅ ContentView.swift
- ✅ VPNCheckerAppIntents.swift

To set target membership:
1. Select a file in the Project Navigator
2. Open the File Inspector (⌥⌘1)
3. Check/uncheck targets in "Target Membership"

### Step 3: Update Info.plist (if needed)

The Mullvad API uses HTTPS, so you shouldn't need to modify App Transport Security settings. But if you have network issues, ensure your Info.plist allows network access.

### Step 4: Build and Run

1. **Select the main app scheme** (not the widget extension)
2. Run on a device or simulator
3. The app should launch and check your VPN status

### Step 5: Add Widget to Home Screen/Desktop

**iOS:**
1. Long press on home screen
2. Tap the "+" button in top left
3. Search for "VPN Checker"
4. Select small or medium size
5. Tap "Add Widget"

**macOS:**
1. Open Notification Center
2. Scroll to bottom
3. Click "Edit Widgets"
4. Search for "VPN Checker"
5. Drag to desktop or notification center

### Step 6: Test Siri Shortcuts (Optional)

Say to Siri:
- "Check my VPN in VPN Checker"
- "Am I connected to VPN in VPN Checker"

Or add the shortcut in the Shortcuts app for custom automation.

## How It Works

### Main App Flow
1. Opens and immediately checks VPN status
2. Shows connection status with IP, location, and organization
3. Refresh button to manually recheck
4. Beautiful UI with color-coded status (green = connected, red = disconnected)

### Widget Flow
1. Widget requests timeline
2. `VPNStatusProvider` calls Mullvad API
3. Parses JSON response
4. Creates timeline entry with status
5. Widget updates UI based on connection state
6. Refreshes automatically every 15 minutes

### API Response (Mullvad)
```json
{
  "ip": "10.0.0.1",
  "country": "Sweden",
  "city": "Stockholm",
  "organization": "Mullvad VPN",
  "mullvad_exit_ip": true,
  "mullvad_server_type": "wireguard"
}
```

### Status Interpretation
- `mullvad_exit_ip: true` → Connected to Mullvad
- `mullvad_exit_ip: false` → Not connected (shows your real IP)

## Customization Options

### Change Update Frequency

In `VPNCheckerWidget.swift`, line ~60:
```swift
// Change from 15 minutes to whatever you want
let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
```

**Note:** iOS limits widget updates. Requesting too frequent updates may be throttled.

### Add Large Widget

1. Add `.systemLarge` to supported families
2. Create `LargeVPNWidgetView` with more detailed info
3. Add it to the switch statement in `VPNWidgetEntryView`

### Switch VPN Providers

To use a different provider (after implementing it):

**In the app:**
```swift
@StateObject private var checker = VPNStatusChecker(provider: ProtonVPNProvider())
```

**In the widget:**
```swift
let status = try await VPNStatusChecker.checkStatus(using: ProtonVPNProvider())
```

### Add Configuration

If you want users to select their VPN provider, you'd need to:
1. Add an `AppIntent` with a provider parameter
2. Switch widget to `AppIntentConfiguration`
3. Store selection in UserDefaults or App Group

## Adding Another VPN Provider

See `ExampleProviders.swift` for templates. Basic steps:

1. Create new file: `[Provider]Provider.swift`
2. Conform to `VPNProvider` protocol
3. Implement `checkStatus()` method
4. Create response model for their API
5. Parse JSON and return `VPNStatus`

Example structure:
```swift
struct MyVPNProvider: VPNProvider {
    let providerName = "MyVPN"
    private let apiURL = URL(string: "https://api.myvpn.com/check")!
    
    func checkStatus() async throws -> VPNStatus {
        // 1. Fetch data
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        
        // 2. Validate response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VPNProviderError.invalidResponse
        }
        
        // 3. Decode JSON
        let decoded = try JSONDecoder().decode(MyResponse.self, from: data)
        
        // 4. Return VPNStatus
        return VPNStatus(
            isConnected: decoded.connected,
            ipAddress: decoded.ip,
            serverLocation: decoded.server,
            country: decoded.country,
            city: decoded.city,
            organization: "MyVPN"
        )
    }
}
```

## Troubleshooting

### Widget Not Appearing
- Make sure you activated the widget extension scheme
- Rebuild the widget extension target
- Delete and re-add the widget

### Network Errors
- Check internet connection
- Verify Mullvad API is accessible: https://am.i.mullvad.net/json
- Check Console app for detailed error messages

### Widget Not Updating
- Widgets have system-imposed limits (typically 15-60 min)
- Try removing and re-adding the widget
- Check widget timeline policy settings

### Build Errors
- Ensure all files have correct target membership
- Clean build folder (Shift+Cmd+K)
- Restart Xcode if needed

## Project Files Summary

| File | Purpose | Targets |
|------|---------|---------|
| VPNProvider.swift | Protocol & models | App + Widget |
| MullvadProvider.swift | Mullvad API | App + Widget |
| VPNStatusChecker.swift | Status service | App + Widget |
| ContentView.swift | Main UI | App only |
| VPNCheckerWidget.swift | Widget views | Widget only |
| VPNCheckerWidgetBundle.swift | Widget entry | Widget only |
| VPNCheckerAppIntents.swift | Siri shortcuts | App only |
| ExampleProviders.swift | Templates | Optional |

## Questions Answered

> **Is there anything you'd like clarified?**

I made some design decisions you might want to adjust:

1. **Privacy**: The widget shows your IP when disconnected. Want to hide it?
2. **Update frequency**: Set to 15 minutes. Want it different?
3. **Widget sizes**: Small & medium only. Want large?
4. **Provider selection**: Currently hardcoded to Mullvad. Want user selection?
5. **Error handling**: Shows error in widget. Want fallback behavior?

Let me know if you want any of these changed! 🎉

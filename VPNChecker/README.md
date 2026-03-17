# VPN Checker Widget

A multiplatform iOS and macOS widget that checks whether you're connected to your VPN using the provider's web service.

## Features

- ✅ Protocol-based architecture for multiple VPN providers
- ✅ Mullvad VPN implementation included
- ✅ iOS and macOS widget support
- ✅ Small and medium widget sizes
- ✅ Beautiful SwiftUI interface
- ✅ Automatic updates every 15 minutes

## Setup Instructions

### 1. Add Widget Extension to Your Project

1. In Xcode, go to **File > New > Target**
2. Select **Widget Extension**
3. Name it `VPNCheckerWidgetExtension`
4. **Uncheck** "Include Configuration Intent" (we don't need it)
5. Click **Finish**
6. When prompted about activating the scheme, click **Activate**

### 2. Configure Targets

#### Widget Extension Target

Add these files to the Widget Extension target:
- `VPNCheckerWidget.swift` (should be there by default)
- `VPNCheckerWidgetBundle.swift` (replace the default bundle file)
- `VPNProvider.swift` ✅
- `MullvadProvider.swift` ✅
- `VPNStatusChecker.swift` ✅

#### Main App Target

Add these files to the main app target:
- `ContentView.swift` (already there)
- `VPNProvider.swift` ✅
- `MullvadProvider.swift` ✅
- `VPNStatusChecker.swift` ✅

### 3. Enable Network Access

Add the following to your **Info.plist** (both app and widget extension):

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>am.i.mullvad.net</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
        </dict>
    </dict>
</dict>
```

Actually, since Mullvad uses HTTPS, you might not need the above. Just ensure your app has internet access.

### 4. Build and Run

1. Select your **main app scheme** and run on a device or simulator
2. Once running, add the widget to your home screen:
   - **iOS**: Long press on home screen > tap "+" > search for "VPN"
   - **macOS**: Open Notification Center > scroll to bottom > click "Edit Widgets" > search for "VPN"

## Architecture

### Protocol-Based Design

The app uses a `VPNProvider` protocol that makes it easy to add new VPN providers:

```swift
protocol VPNProvider {
    var providerName: String { get }
    func checkStatus() async throws -> VPNStatus
}
```

### Adding a New Provider

To add support for another VPN (e.g., ProtonVPN, NordVPN):

1. Create a new file (e.g., `ProtonVPNProvider.swift`)
2. Implement the `VPNProvider` protocol
3. Parse the provider's API response into `VPNStatus`

Example:

```swift
struct ProtonVPNProvider: VPNProvider {
    let providerName = "ProtonVPN"
    
    func checkStatus() async throws -> VPNStatus {
        // Implement API call to ProtonVPN's check endpoint
        // Parse response and return VPNStatus
    }
}
```

4. Update `VPNStatusChecker` to use your new provider:

```swift
let checker = VPNStatusChecker(provider: ProtonVPNProvider())
```

## Widget Refresh Behavior

- **Success**: Updates every 15 minutes
- **Error**: Retries in 5 minutes
- **Manual refresh**: Users can refresh by viewing the widget or using the app

## Files Overview

- **VPNProvider.swift**: Protocol definition and shared models
- **MullvadProvider.swift**: Mullvad-specific API implementation
- **VPNStatusChecker.swift**: Service class for checking status
- **VPNCheckerWidget.swift**: Widget implementation with small/medium sizes
- **VPNCheckerWidgetBundle.swift**: Widget bundle entry point
- **ContentView.swift**: Main app UI

## Customization

### Change Update Frequency

Edit the timeline policy in `VPNCheckerWidget.swift`:

```swift
// Change 15 to your desired minutes
let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
```

### Add Widget Sizes

Add `.systemLarge` to supported families in `VPNCheckerWidget.swift`:

```swift
.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
```

Then implement `LargeVPNWidgetView` in the entry view.

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Privacy

This widget makes network requests to check your VPN status. The API endpoint will see your IP address. For Mullvad, this is their standard check endpoint and doesn't require authentication.

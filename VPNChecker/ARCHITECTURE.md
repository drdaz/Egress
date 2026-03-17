# VPN Checker Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         VPN Checker App                          │
│                                                                   │
│  ┌──────────────────┐              ┌──────────────────┐         │
│  │   ContentView    │              │  Widget (iOS/    │         │
│  │   (Main App UI)  │              │     macOS)       │         │
│  └────────┬─────────┘              └────────┬─────────┘         │
│           │                                 │                    │
│           │                                 │                    │
│           ▼                                 ▼                    │
│  ┌─────────────────────────────────────────────────────┐        │
│  │          VPNStatusChecker (Service)                 │        │
│  │  ┌─────────────────────────────────────────────┐   │        │
│  │  │  @Published var currentStatus: VPNStatus?   │   │        │
│  │  │  func checkStatus() async                   │   │        │
│  │  └─────────────────────────────────────────────┘   │        │
│  └───────────────────┬─────────────────────────────────┘        │
│                      │                                           │
│                      │ uses                                      │
│                      ▼                                           │
│         ┌────────────────────────────┐                          │
│         │   VPNProvider (Protocol)   │                          │
│         │  ┌──────────────────────┐  │                          │
│         │  │ var providerName     │  │                          │
│         │  │ func checkStatus()   │  │                          │
│         │  └──────────────────────┘  │                          │
│         └────────────┬───────────────┘                          │
│                      │                                           │
│         ┌────────────┴────────────┬────────────┐                │
│         │                         │            │                │
│         ▼                         ▼            ▼                │
│  ┌──────────────┐      ┌──────────────┐  ┌──────────┐          │
│  │   Mullvad    │      │   ProtonVPN  │  │   Nord   │          │
│  │   Provider   │      │   Provider   │  │ Provider │          │
│  └──────┬───────┘      └──────┬───────┘  └─────┬────┘          │
│         │                     │                 │               │
└─────────┼─────────────────────┼─────────────────┼───────────────┘
          │                     │                 │
          │ HTTPS               │ HTTPS           │ HTTPS
          ▼                     ▼                 ▼
   ┌──────────────┐      ┌──────────────┐  ┌──────────────┐
   │   Mullvad    │      │  ProtonVPN   │  │   NordVPN    │
   │  API Server  │      │  API Server  │  │  API Server  │
   │am.i.mullvad  │      │api.protonvpn │  │ nordvpn.com  │
   └──────────────┘      └──────────────┘  └──────────────┘
```

## Data Flow

### 1. App Launch / Widget Load
```
User Opens App / Widget Loads
         │
         ▼
VPNStatusChecker.checkStatus()
         │
         ▼
MullvadProvider.checkStatus()
         │
         ▼
URLSession.data(from: URL)
         │
         ▼
Parse JSON Response
         │
         ▼
Create VPNStatus Object
         │
         ▼
Update UI / Widget
```

### 2. Timeline Refresh (Widget Only)
```
System Triggers Update (every 15 min)
         │
         ▼
VPNStatusProvider.getTimeline()
         │
         ▼
Fetch VPN Status
         │
         ▼
Create Timeline Entry
         │
         ▼
Schedule Next Update
         │
         ▼
Widget Renders New State
```

## Data Models

### VPNStatus
```swift
struct VPNStatus {
    let isConnected: Bool        // Main status indicator
    let ipAddress: String         // Current IP address
    let serverLocation: String?   // Server type/name
    let country: String?          // Country location
    let city: String?             // City location
    let organization: String?     // ISP/VPN provider name
}
```

### VPNStatusEntry (Widget)
```swift
struct VPNStatusEntry: TimelineEntry {
    let date: Date           // When this entry was created
    let status: VPNStatus?   // The VPN status (nil if loading)
    var error: String?       // Error message if check failed
}
```

## Protocol Benefits

### Easy to Add Providers
```swift
// Just implement the protocol!
struct NewVPNProvider: VPNProvider {
    let providerName = "NewVPN"
    
    func checkStatus() async throws -> VPNStatus {
        // Your implementation here
        return VPNStatus(...)
    }
}
```

### Easy to Switch Providers
```swift
// In the app
let checker = VPNStatusChecker(provider: NewVPNProvider())

// In the widget
let status = try await VPNStatusChecker.checkStatus(using: NewVPNProvider())
```

### Easy to Test
```swift
// Create a mock provider for testing
struct MockVPNProvider: VPNProvider {
    let providerName = "Mock"
    let mockStatus: VPNStatus
    
    func checkStatus() async throws -> VPNStatus {
        return mockStatus
    }
}

// Use in tests
let mockProvider = MockVPNProvider(
    mockStatus: VPNStatus(isConnected: true, ...)
)
let checker = VPNStatusChecker(provider: mockProvider)
```

## File Dependencies

```
Main App Target:
├── ContentView.swift
│   └── uses VPNStatusChecker
├── VPNStatusChecker.swift
│   └── uses VPNProvider
├── VPNProvider.swift (protocol & models)
├── MullvadProvider.swift
│   └── implements VPNProvider
└── VPNCheckerAppIntents.swift
    └── uses VPNStatusChecker

Widget Extension Target:
├── VPNCheckerWidgetBundle.swift (entry point)
├── VPNCheckerWidget.swift
│   └── uses VPNStatusProvider
├── VPNStatusProvider (in VPNCheckerWidget.swift)
│   └── uses VPNStatusChecker
├── VPNStatusChecker.swift (shared)
├── VPNProvider.swift (shared)
└── MullvadProvider.swift (shared)
```

## API Response Examples

### Mullvad Connected
```json
{
  "ip": "185.65.134.47",
  "country": "Sweden",
  "city": "Stockholm",
  "organization": "Mullvad VPN",
  "mullvad_exit_ip": true,
  "mullvad_server_type": "wireguard"
}
```

### Mullvad Disconnected
```json
{
  "ip": "203.0.113.42",
  "country": "United States",
  "city": "New York",
  "organization": "Example ISP Inc.",
  "mullvad_exit_ip": false,
  "mullvad_server_type": null
}
```

## Widget Rendering States

```
┌─────────────────────────────────────┐
│ Small Widget                        │
├─────────────────────────────────────┤
│                                     │
│         🛡️ (green/red)              │
│                                     │
│        Connected                    │
│         Sweden                      │
│                                     │
└─────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Medium Widget                                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  🛡️      VPN Connected                                 │
│         Stockholm, Sweden                              │
│         Updated 2 minutes ago                          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Key Design Decisions

1. **Protocol-Based Architecture**
   - Easy to extend with new providers
   - Testable and mockable
   - Clean separation of concerns

2. **Shared Code Between App & Widget**
   - VPNProvider protocol
   - VPNStatusChecker service
   - Provider implementations
   - Reduces duplication

3. **Async/Await Throughout**
   - Modern Swift concurrency
   - Clean error handling
   - No callback hell

4. **SwiftUI Native**
   - No UIKit/AppKit needed
   - Works on iOS & macOS
   - Modern, declarative UI

5. **Timeline-Based Updates**
   - Efficient battery usage
   - System-managed scheduling
   - Automatic refresh

## Extension Points

Want to extend the app? Here are some ideas:

1. **Multiple Provider Support**
   - Add provider selection UI
   - Store preference in UserDefaults
   - Use App Group for widget access

2. **Historical Tracking**
   - Store connection history
   - Show uptime statistics
   - Chart connection over time

3. **Notifications**
   - Alert when VPN disconnects
   - Daily status report
   - Battery-friendly background checks

4. **Location Services**
   - Auto-connect by location
   - Different VPNs for different places
   - Location-based rules

5. **Custom Actions**
   - Open VPN app from widget
   - Quick connect shortcut
   - Status in menu bar (macOS)

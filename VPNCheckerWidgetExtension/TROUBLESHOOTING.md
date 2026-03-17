# Widget Troubleshooting Guide

## Widget Shows "Error" Message

If your widget displays an error, here are the most common causes and solutions:

---

## Solution 1: Enable Network Access for Widget Extension ⭐ MOST COMMON

Widgets need explicit permission to access the network. You need to add the network entitlement to your **Widget Extension target**.

### Steps:

1. Select your project in the Project Navigator
2. Select the **Widget Extension target** (e.g., `VPNCheckerWidgetExtension`)
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Search for and add **"Outgoing Connections (Client)"**
   - This adds the `com.apple.security.network.client` entitlement

### For macOS specifically:
You may also need:
- **Incoming Connections (Server)** (usually not needed)
- Make sure **App Sandbox** is enabled

### Alternative: Check Info.plist
Ensure your widget extension's Info.plist has network access (usually automatic with capabilities).

---

## Solution 2: Check Console for Detailed Errors

The widget now prints detailed error messages to the console:

### View Console Output:

**Xcode Console:**
1. Run your app with the widget extension scheme
2. Look for lines starting with `❌ Widget`
3. Note the exact error message

**macOS Console App:**
1. Open **Console.app**
2. Select your device/simulator
3. Search for "VPNChecker" or "Widget"
4. Look for error messages

**Common Error Messages:**

```
❌ Widget timeline error: The Internet connection appears to be offline
→ No internet connection (check device)

❌ Widget timeline error: A server with the specified hostname could not be found
→ DNS issue or VPN API is down

❌ Widget timeline error: The network connection was lost
→ Network interruption

❌ Widget timeline error: The request timed out
→ API is slow or unreachable
```

---

## Solution 3: Verify Target Membership

Ensure these files are in the **Widget Extension** target:

- ✅ `VPNCheckerWidget.swift`
- ✅ `VPNCheckerWidgetBundle.swift`
- ✅ `VPNProvider.swift`
- ✅ `MullvadProvider.swift`
- ✅ `VPNStatusChecker.swift`

To check:
1. Select each file in Project Navigator
2. Open File Inspector (⌥⌘1)
3. Verify "Target Membership" includes the widget extension

---

## Solution 4: Test the API Manually

Verify the Mullvad API is accessible:

### In Terminal:
```bash
curl https://am.i.mullvad.net/json
```

You should see JSON output like:
```json
{
  "ip": "123.45.67.89",
  "country": "United States",
  "city": "New York",
  "organization": "Example ISP",
  "mullvad_exit_ip": false,
  "mullvad_server_type": null
}
```

### In Safari:
Open: https://am.i.mullvad.net/json

If this doesn't work, the API might be temporarily down or blocked.

---

## Solution 5: Rebuild and Reinstall

Sometimes Xcode needs a clean build:

1. **Product → Clean Build Folder** (⇧⌘K)
2. **Delete the app** from your device/simulator
3. **Rebuild** (⌘B)
4. **Run** the app again
5. **Remove and re-add** the widget

---

## Solution 6: Check Simulator/Device Settings

### iOS/iPadOS Simulator:
- Ensure **"Connect Hardware Keyboard"** is not interfering
- Try restarting the simulator: Device → Restart

### macOS:
- System Settings → Privacy & Security → Network
- Ensure your widget extension is allowed

### Real Device:
- Check if you have internet connection
- Try airplane mode off/on
- Check if VPN (if you use one) is blocking widget network access

---

## Solution 7: Add Better Error Display

The widget now shows detailed error messages. Check what the widget displays:

- **"No internet connection"** → Device offline
- **"Cannot reach VPN API"** → DNS or firewall issue
- **"Network error: -1009"** → No internet (offline)
- **"Network error: -1001"** → Request timeout
- **"The data couldn't be read because it isn't in the correct format"** → API response changed

---

## Solution 8: Enable App Transport Security (if needed)

If you see SSL/TLS errors, check your Info.plist (both app and widget):

The Mullvad API uses HTTPS, so this shouldn't be needed, but if you have custom ATS settings:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

Do NOT set `NSAllowsArbitraryLoads` to `true` for production.

---

## Solution 9: Test with Mock Data

To verify the widget UI works, temporarily use mock data:

In `VPNCheckerWidget.swift`, modify `getTimeline`:

```swift
func getTimeline(in context: Context, completion: @escaping (Timeline<VPNStatusEntry>) -> ()) {
    // TEMPORARY: Use mock data to test widget UI
    let mockStatus = VPNStatus(
        isConnected: true,
        ipAddress: "10.0.0.1",
        serverLocation: "wireguard",
        country: "Sweden",
        city: "Stockholm",
        organization: "Mullvad VPN"
    )
    let entry = VPNStatusEntry(date: Date(), status: mockStatus)
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
    
    // Remove above and uncomment below once network works:
    // [original async code]
}
```

If this works, the issue is definitely network-related.

---

## Solution 10: Check for API Changes

The Mullvad API might have changed. Verify the response structure matches:

```swift
private struct MullvadResponse: Codable {
    let ip: String
    let country: String
    let city: String
    let organization: String
    let mullvadExitIP: Bool  // Check this matches API
    let mullvadServerType: String?
    
    enum CodingKeys: String, CodingKey {
        case ip
        case country
        case city
        case organization
        case mullvadExitIP = "mullvad_exit_ip"  // Must match JSON key
        case mullvadServerType = "mullvad_server_type"
    }
}
```

---

## Quick Checklist

Run through this checklist:

- [ ] Widget Extension target has "Outgoing Connections (Client)" capability
- [ ] All required files are in Widget Extension target
- [ ] Console shows detailed error messages
- [ ] Mullvad API works in browser/curl
- [ ] Clean build and reinstall
- [ ] Device has internet connection
- [ ] Widget removed and re-added to home screen
- [ ] Main app works correctly

---

## Still Not Working?

### Check Console Output First!

Run the widget and check Xcode's console for the exact error:

```
❌ Widget timeline error: [ERROR MESSAGE HERE]
```

This will tell you exactly what's wrong. Common errors:

| Error | Meaning | Fix |
|-------|---------|-----|
| "not connected to Internet" | Offline | Check connection |
| "cannot connect to host" | DNS/firewall | Check network settings |
| "couldn't be read" | JSON parsing | API response changed |
| "The operation couldn't be completed" | Generic network | Add network capability |

### Get More Details:

Add this to `MullvadProvider.swift` for debugging:

```swift
func checkStatus() async throws -> VPNStatus {
    print("🔍 Fetching from: \(apiURL)")
    
    let (data, response) = try await URLSession.shared.data(from: apiURL)
    
    print("📦 Response: \(response)")
    print("📄 Data: \(String(data: data, encoding: .utf8) ?? "nil")")
    
    // ... rest of code
}
```

This will show you the exact API response in the console.

---

## Most Likely Solution

**99% of the time, it's missing network capabilities!**

Go to your Widget Extension target → Signing & Capabilities → Add "Outgoing Connections (Client)"

Then clean build and reinstall the widget.

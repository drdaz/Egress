# macOS Widget Update Fix

## Problem Summary

The macOS widget was showing stale data (24+ hours old) while the iOS widget updated correctly. This occurred on multiple machines.

## Root Cause

**The app was not notifying widgets to refresh when status data changed.**

### Key Issues Identified:

1. **No `WidgetCenter.shared.reloadAllTimelines()` calls**: The app never told widgets to update when new data was available
2. **macOS aggressive caching**: macOS widgets cache timelines more aggressively than iOS widgets
3. **15-minute refresh interval**: Widgets only updated every 15 minutes via timeline policy, not when user manually checked status
4. **Timer-based updates didn't notify widgets**: The menu bar's 30-second timer updated the menu bar but not the widget

## The Fix

Added `WidgetCenter.shared.reloadAllTimelines()` calls in three critical locations:

### 1. VPNCheckerApp.swift - Menu Bar Refresh
```swift
@objc func refreshStatus() {
    Task {
        await checker.checkStatus()
        await updateMenuStatus()
        await updateMenuBarIcon()
        
        // ✅ NEW: Refresh widgets when menu bar updates
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

### 2. VPNCheckerApp.swift - Auto Update Timer
```swift
private func updateMenuBarIcon() async {
    // ... status checking code ...
    
    await updateMenuStatus()
    
    // ✅ NEW: Refresh widgets when status updates
    WidgetCenter.shared.reloadAllTimelines()
}
```

### 3. ContentView.swift - Manual Status Check
```swift
Button {
    Task {
        await checker.checkStatus()
        // ✅ NEW: Refresh widgets after checking status
        WidgetCenter.shared.reloadAllTimelines()
    }
} label: {
    Label("Check Status", systemImage: "arrow.clockwise")
        .frame(maxWidth: .infinity)
}
```

### 4. ContentView.swift - App Launch
```swift
.task {
    await checker.checkStatus()
    // ✅ NEW: Refresh widgets when app appears
    WidgetCenter.shared.reloadAllTimelines()
}
```

## Why This Fixes It

### iOS vs macOS Widget Behavior Differences

**iOS:**
- Widgets refresh more readily
- System is more aggressive about updating widgets
- Timeline policies are respected more strictly
- Background app refresh helps keep widgets current

**macOS:**
- Widgets aggressively cache timelines for performance
- Desktop widgets persist longer without updates
- Timeline policies are treated as suggestions rather than guarantees
- Widget extension process can run for extended periods with cached data
- **Requires explicit `WidgetCenter.shared.reloadAllTimelines()` calls** to ensure updates

### What `reloadAllTimelines()` Does

- Forces WidgetKit to call `getTimeline(in:completion:)` again
- Bypasses cached timeline data
- Ensures widgets show the most recent data
- Works on both iOS and macOS (but more critical on macOS)

## Testing the Fix

### Before:
- macOS widget showed stale data for 24+ hours
- Only updated when the 15-minute timeline expired
- Manual refresh in menu bar didn't update widget
- Widget showed old VPN status even when connection changed

### After:
- Widget updates immediately when menu bar refreshes (every 30 seconds)
- Widget updates when user clicks "Refresh" in menu bar
- Widget updates when user opens main app
- Widget updates when user clicks "Check Status" button
- Widget still falls back to 15-minute auto-refresh if app isn't running

## Best Practices Applied

1. **Update widgets when app has new data**: Any time the app fetches new VPN status, notify widgets
2. **Update on user actions**: When user explicitly refreshes, update widgets
3. **Update on app lifecycle events**: When app launches or appears, refresh widgets
4. **Keep timeline policies**: The 15-minute fallback ensures widgets update even if app isn't used

## Additional Notes

### Why Timers Alone Don't Work
The menu bar's 30-second timer updates the menu bar icon by calling `checkStatus()`, but without `reloadAllTimelines()`, the widget never knew to update. The widget and app are separate processes.

### Widget vs App Communication
- Widgets run in a separate extension process
- App cannot directly pass data to widgets
- Communication happens via:
  - `WidgetCenter.shared.reloadAllTimelines()` (tells widget to refresh)
  - App Groups (for shared data storage, if needed)
  - Timeline policies (automatic refresh intervals)

### Performance Considerations
- `reloadAllTimelines()` is lightweight - it just triggers a timeline fetch
- The actual network call happens once (in the app) and once (in the widget timeline provider)
- On macOS, this is essential; on iOS, it's good practice

## Related Files Modified

- ✅ `VPNCheckerApp.swift` - Added WidgetKit import and reload calls
- ✅ `ContentView.swift` - Added WidgetKit import and reload calls

## Verification Steps

1. **Clean and rebuild** the project (⇧⌘K, then ⌘B)
2. **Remove old widget** from desktop
3. **Run the app** on macOS
4. **Add the widget** to desktop
5. **Click "Refresh"** in menu bar - widget should update immediately
6. **Wait 30 seconds** - widget should update with timer
7. **Open main app** - widget should update when app appears

## Success Criteria

✅ Widget updates within seconds of menu bar refresh  
✅ Widget shows current data matching menu bar icon  
✅ Widget updates when user interacts with app  
✅ Widget updates automatically via timer (every 30s via app, or 15min via timeline)  
✅ No more 24-hour stale data  

---

**Date Fixed**: April 3, 2026  
**Platform Affected**: macOS (iOS was working correctly)  
**Severity**: High (widget showed incorrect data for extended periods)  
**Fix Type**: Missing widget refresh notifications  

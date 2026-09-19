# Timer and API Call Lifecycle Fix

## Problem
When navigating between tabs (Assigned, Processing, Scheduled, Completed, Delivered), the timers and API calls from the previous page continued running in the background. This caused:
- Unnecessary API calls to endpoints that weren't being displayed
- Network traffic for pages the user wasn't viewing
- Timers continuing to count down even when navigating away
- Potential performance issues and battery drain

## Root Cause
The screens (`HomeScreen`, `ProcessingTaskPage`, and `ScheduledTaskPage`) were using `AutomaticKeepAliveClientMixin` with `wantKeepAlive => true`. This keeps widgets alive in the PageView even when not visible, which is normally good for preserving state, but meant:
1. Timers started in `initState()` never stopped
2. `dispose()` was never called when switching tabs
3. Periodic API calls (`_liveUpdateTimer`) continued running

## Solution
All three affected screens now:

### 1. **Listen to Navigation State**
- Changed from `StatefulWidget` to `ConsumerStatefulWidget` (Riverpod)
- Added tracking variable `_isPageActive` to know when the screen is visible
- Use `didChangeDependencies()` to watch the `bottomNavIndexProvider`

### 2. **Lifecycle Management**
- **When page becomes active** (user navigates to it):
  - Set `_isPageActive = true`
  - Load tasks fresh from API (silently, without loading indicator on subsequent visits)
  - Start 10-second API polling timer **from scratch** (always starts at 0)
  - Escalation timers are calculated fresh from task data each time
  
- **When page becomes inactive** (user navigates away):
  - Set `_isPageActive = false`
  - Stop the 10-second API polling timer only
  - Escalation countdown timers naturally stop (will be recalculated when returning)

### 3. **Timer Behavior**
- **10-second API polling timer**: Always starts fresh at 0 when you navigate to a page
  - No need to track where it was - just restart from scratch
  - This ensures consistent polling intervals
  
- **Escalation countdown timers**: Recalculated from server data each time you return
  - Server timestamps are the source of truth
  - Timers show accurate time remaining based on when task was assigned/started
  - No state preservation needed - API data provides accurate values

## Files Modified

### 1. `lib/Screens/home_screen.dart` (Assigned Tasks - Index 0)
- Converted to `ConsumerStatefulWidget`
- Added navigation state tracking
- Stops timers when navigating away from index 0

### 2. `lib/Screens/processing_task_screen.dart` (Processing Tasks - Index 1)
- Converted to `ConsumerStatefulWidget`
- Added navigation state tracking
- Stops timers and API calls when navigating away from index 1

### 3. `lib/Screens/scheduled_task_page.dart` (Scheduled Tasks - Index 2)
- Converted to `ConsumerStatefulWidget`
- Added navigation state tracking
- Stops timers when navigating away from index 2

## Behavior

### Before Fix
```
User Flow:
1. Open Assigned screen → Timers start, API calls every 10s
2. Navigate to Completed screen
3. ❌ Assigned screen timers still running
4. ❌ API calls still happening every 10s
5. Network log shows requests for assigned tasks even though user is on completed screen
```

### After Fix
```
User Flow:
1. Open Assigned screen → Load data, start 10s API timer from 0
2. Navigate to Completed screen
3. ✅ 10-second API timer stopped
4. ✅ No more API calls happening
5. Navigate back to Assigned screen
6. ✅ Load fresh data, 10s API timer starts from 0 again
7. ✅ Escalation timers show accurate countdown based on server time
```

## Debug Logs
The fix includes debug print statements to track lifecycle:
- 🟢 Green circle: Page became active - loading fresh data and starting 10s API timer
- 🔴 Red circle: Page became inactive - stopping 10s API timer
- 🛑 Stop symbol: Stopping live updates timer
- ⏰ Clock: 10-second timer fired - reloading tasks

## Testing
To verify the fix:
1. Open the app and go to Assigned or Processing screen
2. Open DevTools network inspector
3. Observe API calls happening every 10 seconds
4. Navigate to Completed or Delivered screen
5. ✅ API calls should stop immediately
6. Navigate back to Assigned or Processing
7. ✅ API calls should resume

## Benefits
- ✅ API calls only happen on the active page
- ✅ Reduced network traffic and server load
- ✅ Better battery life
- ✅ Improved app performance
- ✅ Timers accurately reflect user's current view
- ✅ State is preserved (thanks to AutomaticKeepAliveClientMixin)
- ✅ Smooth user experience with no data loss

## Notes
- `AutomaticKeepAliveClientMixin` is still enabled to preserve scroll position and state
- The completed and delivered pages don't need this fix as they only load data once in `initState()`
- App lifecycle changes (app going to background) are still handled separately via `WidgetsBindingObserver`


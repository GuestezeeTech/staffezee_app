# Timer Lifecycle Fix - Testing Guide

## Quick Test

### Test 1: Verify API Calls Stop When Navigating Away

1. **Open the app** and log in
2. **Navigate to Assigned tab** (first tab)
   - You should see tasks loading
   - Check the console logs - you should see:
     ```
     🟢 HomeScreen: Page became active - starting timers and API calls
     ⏰ HomeScreen: 10-second timer fired - reloading assigned tasks
     ```

3. **Open Network Inspector** (in your development tools)
   - You should see API calls happening every 10 seconds to `/assigned-tasks` endpoint

4. **Navigate to Completed tab** (fourth tab)
   - Check the console logs - you should see:
     ```
     🔴 HomeScreen: Page became inactive - stopping timers and API calls
     ⏸️ HomeScreen: Pausing all timers and API calls
     🛑 HomeScreen: Stopping live updates timer
     ```
   - **Network inspector should show NO more calls to `/assigned-tasks`**

5. **Wait 30 seconds** on the Completed tab
   - Verify no API calls are being made to `/assigned-tasks`

6. **Navigate back to Assigned tab**
   - Console should show:
     ```
     🟢 HomeScreen: Page became active - starting timers and API calls
     ```
   - **API calls should resume** (every 10 seconds)

### Test 2: Verify Processing Tab Timers

1. **Accept a task** from the Assigned tab to move it to Processing
2. **Navigate to Processing tab** (second tab)
   - You should see tasks with countdown timers
   - Console should show:
     ```
     🟢 ProcessingTaskPage: Page became active - starting timers and API calls
     ```

3. **Watch the timers count down** for a few seconds
4. **Navigate to Scheduled tab** (third tab)
   - Console should show:
     ```
     🔴 ProcessingTaskPage: Page became inactive - stopping timers and API calls
     ⏸️ ProcessingTaskPage: Pausing all timers and API calls
     ```

5. **Wait 20 seconds** on the Scheduled tab
6. **Navigate back to Processing tab**
   - Timers should **resume from where they left off** (or refresh if API call updated them)
   - Console shows page became active again

### Test 3: Verify Scheduled Tab Timers

1. **Navigate to Scheduled tab** (third tab)
   - Console should show:
     ```
     🟢 ScheduledTaskPage: Page became active - starting timers
     ```

2. **Navigate to Delivered tab** (fifth tab)
   - Console should show:
     ```
     🔴 ScheduledTaskPage: Page became inactive - stopping timers
     ⏸️ ScheduledTaskPage: Pausing all timers
     ```

3. **Navigate back to Scheduled tab**
   - Timers should restart
   - Console shows page became active

## Expected Console Output Pattern

When navigating: **Assigned → Processing → Completed**

```
🟢 HomeScreen: Page became active - starting timers and API calls
⏰ HomeScreen: 10-second timer fired - reloading assigned tasks
🔴 HomeScreen: Page became inactive - stopping timers and API calls
⏸️ HomeScreen: Pausing all timers and API calls
🛑 HomeScreen: Stopping live updates timer
🟢 ProcessingTaskPage: Page became active - starting timers and API calls
⏰ ProcessingTaskPage: 10-second timer fired - reloading processing tasks
🔴 ProcessingTaskPage: Page became inactive - stopping timers and API calls
⏸️ ProcessingTaskPage: Pausing all timers and API calls
🛑 ProcessingTaskPage: Stopping live updates timer
```

## Network Monitor Check

### ✅ CORRECT Behavior (After Fix)
- When on **Assigned tab**: `/api/assigned-tasks` calls every 10s
- When on **Processing tab**: `/api/processing-tasks` calls every 10s
- When on **Completed tab**: NO periodic API calls (only on manual refresh)
- Only ONE endpoint should be called at a time

### ❌ INCORRECT Behavior (Before Fix)
- Multiple endpoints being called simultaneously
- Calls continue even when not on that tab
- Network traffic continues in background

## Performance Benefits

After the fix, you should notice:
- ✅ Reduced network traffic (only one tab's API calls at a time)
- ✅ Better battery life (fewer background operations)
- ✅ Improved app responsiveness
- ✅ Lower server load

## Troubleshooting

If timers are still running in the background:
1. Make sure you're running the latest code
2. Do a **Hot Restart** (not just Hot Reload) to ensure all changes are applied
3. Check the console logs to verify the lifecycle messages appear
4. Verify the `bottomNavIndexProvider` is working correctly in `navigation_page.dart`

## Regression Check

Verify these still work correctly:
- ✅ App lifecycle (minimize/restore app) still pauses/resumes correctly
- ✅ Timers display correctly when on each tab
- ✅ Data refreshes when navigating back to a tab
- ✅ Pull-to-refresh still works
- ✅ Scroll position is preserved when switching tabs


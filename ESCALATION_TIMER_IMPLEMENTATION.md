# Escalation Timer Implementation

## Overview
This document describes the implementation of the escalation timer system for staff tasks in the GuestEzee Staff App.

## Problem Statement
The app needs to display accurate escalation times for each task assigned to staff members. The challenge is that:
1. The website hits the task API every 10 seconds with its own escalation timer running on the server
2. If we simply use the local escalation time value directly, we'll be out of sync with the server
3. Each task should have its timer start from the moment it was assigned and continue until completion

## Solution

### 1. New Service: `EscalationTimerService`
**Location:** `lib/Services/escalation_timer_service.dart`

This service provides centralized escalation time management with the following key methods:

#### Key Methods:

- **`getStaffEscalationTime()`**: Retrieves the staff's escalation time (in minutes) from the user's hierarchy data stored in local storage.

- **`calculateRemainingEscalationTime(task)`**: Calculates the actual remaining escalation time for a specific task by:
  1. Getting the staff's escalation time from local storage
  2. Finding the assignment time from the task's `time_line` array (where status is "Assigned")
  3. Calculating elapsed time since assignment
  4. Subtracting elapsed time from total escalation time to get remaining time

- **`initializeTaskTimers(tasks)`**: Initializes a list of Duration objects for multiple tasks, calculating the correct remaining time for each.

- **`isTaskEscalated(task)`**: Checks if a task has been escalated based on API status or remaining time.

- **`formatDuration(duration)`**: Formats a Duration to display string (e.g., "02:30 m").

### 2. Login Integration
**File:** `lib/Screens/login_page.dart`

The login process now:
1. Saves the escalation time from the user's `hierarchy.escalationTime` field to local storage
2. This happens automatically during successful login
3. The escalation time is persisted for use throughout the app session

### 3. Task Screen Updates

All task screens have been updated to use the `EscalationTimerService`:

#### Updated Files:
- `lib/Screens/home_screen.dart` (Assigned tasks)
- `lib/Screens/processing_task_screen.dart` (Processing tasks)
- `lib/Screens/scheduled_task_page.dart` (Scheduled tasks)

#### Changes Made:
1. Import `EscalationTimerService`
2. Replace hardcoded timer initialization with `EscalationTimerService.initializeTaskTimers(tasks)`
3. Added proper timer disposal and safety checks

## How It Works

### Step-by-Step Flow:

1. **Login:**
   - User logs in with employee ID and PIN
   - App receives login response with hierarchy data
   - `escalationTime` from `hierarchy` object is saved to local storage

2. **Task Assignment:**
   - When a task is assigned to the staff member, the server records the assignment time in the task's `time_line` array
   - The API returns this task data to the mobile app

3. **Timer Calculation:**
   - App receives task data from API
   - `EscalationTimerService.calculateRemainingEscalationTime()` is called for each task
   - Service extracts the assignment time from `time_line` (where status is "Assigned")
   - Calculates: `remainingTime = staffEscalationTime - (currentTime - assignmentTime)`
   - Returns the calculated Duration

4. **Timer Display:**
   - Each task displays its calculated remaining time
   - Timer counts down every second
   - When timer reaches zero, task is marked as escalated

5. **Task Progression:**
   - The timer continues running even when task moves from "Assigned" to "Processing"
   - Timer uses the original assignment time throughout the task lifecycle
   - Timer stops only when task is marked as "Completed"

## Edge Cases Handled

1. **Missing Assignment Time:** If no "Assigned" status is found in timeline, the service falls back to the first non-ASAP/non-Scheduled status.

2. **Already Escalated Tasks:** If calculated time is negative (task is overdue), returns `Duration.zero` and UI shows escalated state.

3. **Missing Escalation Time:** If staff's escalation time is not found, defaults to 30 minutes.

4. **Invalid Date/Time Formats:** Robust parsing with fallback mechanisms for different date/time formats.

5. **Timer Cleanup:** All timers are properly disposed when screens are unmounted or tasks are refreshed.

6. **App Lifecycle:** Timers are paused when app goes to background and resumed when app comes back to foreground.

## Example Calculation

### Scenario:
- Staff escalation time: 2 minutes (from hierarchy)
- Task assigned at: 2025-10-09 19:05:57
- Current time: 2025-10-09 19:06:30
- Elapsed time: 33 seconds
- Remaining time: 2 minutes - 33 seconds = 1 minute 27 seconds

The timer will display "01:27 m" and count down.

## Benefits

1. **Accurate Sync:** Timers stay in sync with the server by calculating from the actual assignment time
2. **Continuous Timer:** Same timer continues from assignment through processing to completion
3. **No Race Conditions:** Uses server timestamps rather than local time for calculations
4. **Flexible:** Works with different escalation times for different staff members
5. **Robust:** Handles edge cases and missing data gracefully

## Testing Recommendations

1. Test with different escalation times (1 min, 2 min, 5 min, etc.)
2. Test task progression from Assigned → Processing → Completed
3. Test with tasks that are already escalated
4. Test app going to background and coming back
5. Test with poor network conditions (delayed API responses)
6. Test with multiple simultaneous tasks

## Notes

- The implementation follows Flutter best practices with proper resource disposal
- All calculations are done in local time to avoid timezone issues
- The service is stateless and can be used from anywhere in the app
- Print statements are included for debugging (can be removed in production)


# Escalation Timer - Testing Guide

## Pre-Test Setup

1. Ensure you have a test user with:
   - Valid employee ID
   - Valid PIN
   - `hierarchy.escalationTime` set in the backend (e.g., 2 minutes)

2. Have access to the admin panel to assign tasks

## Test Scenarios

### Test 1: Login and Escalation Time Storage
**Objective:** Verify escalation time is saved during login

**Steps:**
1. Open the app
2. Enter valid employee ID and PIN
3. Click Login

**Expected Result:**
- Login successful
- Navigate to home screen
- Escalation time from hierarchy is saved to local storage

**Verification:**
- Check Hive storage for `staff_escalation_time` key
- Value should match the `escalationTime` from user's hierarchy

---

### Test 2: Assigned Task Timer Display
**Objective:** Verify timer calculates correctly for new assigned tasks

**Setup:**
- Assign a task to the staff member from admin panel
- Note the assignment time

**Steps:**
1. Open the app (or wait for auto-refresh)
2. Navigate to "Assigned" tab (home screen)
3. Observe the timer on the newly assigned task

**Expected Result:**
- Timer displays the correct remaining time
- Timer format: "MM:SS" or "HH:MM m" depending on duration
- Timer counts down every second

**Example:**
- If escalation time is 2 minutes and task was assigned 30 seconds ago
- Timer should show approximately 01:30

---

### Test 3: Timer Persistence Across Task Status Changes
**Objective:** Verify timer continues from assignment when task moves to processing

**Steps:**
1. Have a task in "Assigned" status
2. Note the timer value (e.g., 01:45)
3. Accept the task (moves to "Processing")
4. Navigate to "Processing" tab
5. Observe the timer

**Expected Result:**
- Timer continues from where it was in assigned state
- Uses the same assignment time as reference
- Timer doesn't reset to full escalation time

---

### Test 4: Already Escalated Tasks
**Objective:** Verify tasks that are already escalated display correctly

**Setup:**
- Have a task that was assigned more than escalation time ago
- Task status should be "Escalated"

**Steps:**
1. View the escalated task
2. Check the timer display

**Expected Result:**
- Timer shows "00:00 m" or similar
- Task is visually marked as escalated (red indicator)
- Timer doesn't go negative

---

### Test 5: Multiple Tasks with Different Times
**Objective:** Verify each task has its own independent timer

**Setup:**
- Have 3 tasks assigned at different times:
  - Task A: assigned 30 seconds ago
  - Task B: assigned 1 minute ago
  - Task C: assigned 1 minute 30 seconds ago

**Steps:**
1. View all tasks in "Assigned" tab
2. Check timer for each task

**Expected Result:**
- Task A timer: ~01:30 remaining
- Task B timer: ~01:00 remaining
- Task C timer: ~00:30 remaining
- All timers count down independently

---

### Test 6: App Background/Foreground
**Objective:** Verify timers update correctly when app goes to background and comes back

**Steps:**
1. View a task with timer showing 01:30
2. Press home button (app goes to background)
3. Wait 30 seconds
4. Open app again

**Expected Result:**
- Timer recalculates based on assignment time
- Shows approximately 01:00 (not 01:30)
- Timer doesn't "freeze" or show stale data

---

### Test 7: Live Updates (10 Second Polling)
**Objective:** Verify timers update correctly during background polling

**Steps:**
1. Keep app open on assigned tasks screen
2. Wait for 10-second auto-refresh
3. Observe task timers

**Expected Result:**
- Tasks refresh every 10 seconds
- Timer values recalculate correctly
- No timer jumps or inconsistencies
- Old timers are disposed properly (no memory leak)

---

### Test 8: Task Completion
**Objective:** Verify timer stops when task is completed

**Steps:**
1. Have a task in "Processing" status
2. Mark task as "Completed"
3. Check "Completed" tab

**Expected Result:**
- Task moves to completed tab
- No timer displays (or shows final time)
- Timer stops counting

---

### Test 9: Different Escalation Times
**Objective:** Verify system works with different escalation time values

**Steps:**
1. Test with escalation time = 1 minute
2. Test with escalation time = 5 minutes
3. Test with escalation time = 10 minutes

**Expected Result:**
- Timer correctly calculates for each escalation time
- No hardcoded values override the calculation

---

### Test 10: Edge Cases

#### 10a. Missing Assignment Time
**Setup:** Task without "Assigned" status in timeline

**Expected:** Falls back to first non-ASAP/non-Scheduled status time

#### 10b. Invalid Date Format
**Setup:** Task with malformed date/time in timeline

**Expected:** Uses default escalation time (30 minutes)

#### 10c. Network Delay
**Setup:** Slow network when fetching tasks

**Expected:** Timer calculates from server timestamp, not local time

---

## Performance Tests

### Memory Leak Test
**Objective:** Ensure no memory leaks from timers

**Steps:**
1. Open app
2. Navigate between tabs multiple times
3. Let live updates run for 5 minutes
4. Check memory usage

**Expected Result:**
- Memory usage stable
- No continuous memory growth
- Timers properly disposed

---

## Bug Reports Template

If you find issues, please report with:

```
**Issue:** Brief description
**Escalation Time:** X minutes
**Task Assignment Time:** YYYY-MM-DD HH:MM:SS
**Current Time:** YYYY-MM-DD HH:MM:SS
**Expected Timer:** MM:SS
**Actual Timer:** MM:SS
**Task Status:** Assigned/Processing/Escalated
**Steps to Reproduce:**
1. Step 1
2. Step 2
3. ...
```

---

## Quick Verification Checklist

- [ ] Login saves escalation time
- [ ] Assigned tasks show correct timer
- [ ] Processing tasks continue same timer
- [ ] Escalated tasks show correctly
- [ ] Multiple tasks have independent timers
- [ ] App background/foreground works
- [ ] Live updates work correctly
- [ ] Task completion stops timer
- [ ] Different escalation times work
- [ ] No memory leaks
- [ ] Edge cases handled gracefully


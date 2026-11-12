# Department-Specific Escalation Timer Implementation

## Overview
Implemented dynamic escalation timer calculation based on task department. Each department (EHK, FO, F&B, etc.) can have its own escalation time, and tasks are assigned the correct timer based on their service category.

## Problem Statement
Previously, all tasks used a single escalation time regardless of department. With staff members now belonging to multiple departments, each with different escalation times, we need to:
1. Store escalation times for each department separately
2. Match tasks to their department-specific escalation time
3. Calculate timers dynamically based on task category

## Implementation Details

### 1. Data Structure

**Staff Hierarchy** (from login API):
```json
{
  "hierarchy": [
    {
      "department": "EHK",
      "designation": "EHK Staff",
      "escalationTime": 1,
      "id": 8
    },
    {
      "department": "FO",
      "designation": "FO Staff",
      "escalationTime": 2,
      "id": 9
    }
  ]
}
```

**Task Response** (from getAll API):
```json
{
  "service": {
    "category": "EHK",
    "service_name": "Room spray",
    "service_id": 456
  },
  "status": "Assigned",
  "time_line": [...]
}
```

### 2. LocalStorageService Updates

**New Methods**:

```dart
/// Get escalation times mapped by department
/// Returns Map<String, int> where key = department, value = minutes
static Map<String, int> get departmentEscalationTimes;

/// Get escalation time for a specific department
static int? getEscalationTimeForDepartment(String? department);

/// Save department escalation times to local storage
static Future<void> saveDepartmentEscalationTimes(Map<String, int> escalationTimes);

/// Get saved department escalation times from local storage
static Map<String, int> getSavedDepartmentEscalationTimes();
```

**Storage Format**:
```dart
{
  "EHK": 1,  // 1 minute
  "FO": 2,   // 2 minutes
  "F&B": 15  // 15 minutes
}
```

**File**: `lib/Services/local_storage_service.dart`

### 3. Login Page Updates

During login, extract all escalation times from the hierarchy array:

```dart
// Extract escalation time for each department
final Map<String, int> departmentEscalationTimes = {};

if (hierarchy is List && hierarchy.isNotEmpty) {
  for (final hierarchyEntry in hierarchy) {
    final String? department = hierarchyEntry['department'];
    final dynamic escalationTime = hierarchyEntry['escalationTime'];
    
    if (department != null && escalationTime != null) {
      departmentEscalationTimes[department] = escalationTime;
      print('💾 Saved escalation time for $department: $escalationTime minutes');
    }
  }
}

// Save to local storage
await LocalStorageService.saveDepartmentEscalationTimes(departmentEscalationTimes);
```

**File**: `lib/Screens/login_page.dart`

### 4. EscalationTimerService Updates

**New Method**: `getEscalationTimeForTask()`

```dart
/// Get escalation time for a specific task based on its department/category
static int? getEscalationTimeForTask(Map<String, dynamic> task) {
  // Extract department from task's service category
  final String? taskDepartment = task['service']?['category'];
  
  if (taskDepartment == null) {
    return getStaffEscalationTime(); // Fallback
  }

  // Get department-specific escalation time
  final int? escalationTime = 
      LocalStorageService.getEscalationTimeForDepartment(taskDepartment);
  
  if (escalationTime != null) {
    print('✅ Found escalation time for $taskDepartment: $escalationTime minutes');
    return escalationTime;
  }
  
  return getStaffEscalationTime(); // Fallback
}
```

**Updated Methods**:
- `calculateRemainingEscalationTime()` - Now uses task-specific escalation time
- `initializeTaskTimers()` - Each task gets its own department-specific timer

**File**: `lib/Services/escalation_timer_service.dart`

## Flow Diagram

```
Login
  ↓
Extract hierarchy array
  ↓
For each hierarchy entry:
  - department: "EHK" → escalationTime: 1
  - department: "FO" → escalationTime: 2
  ↓
Save to local storage: {"EHK": 1, "FO": 2}
  ↓
───────────────────────────────────────
  ↓
Task arrives with service.category = "EHK"
  ↓
EscalationTimerService.getEscalationTimeForTask(task)
  ↓
Read task['service']['category'] → "EHK"
  ↓
LocalStorageService.getEscalationTimeForDepartment("EHK") → 1 minute
  ↓
Calculate timer: Now - AssignmentTime vs 1 minute
  ↓
Display countdown in UI
```

## Example Scenarios

### Scenario 1: EHK Task
**Task Data**:
```json
{
  "service": {"category": "EHK"},
  "status": "Assigned",
  "time_line": [{"status": "Assigned", "time": "17:32:05"}]
}
```

**Calculation**:
- Department: EHK
- Escalation Time: 1 minute (from hierarchy)
- Assignment Time: 17:32:05
- Current Time: 17:32:30
- Elapsed: 25 seconds
- Remaining: 35 seconds

### Scenario 2: FO Task
**Task Data**:
```json
{
  "service": {"category": "FO"},
  "status": "Assigned",
  "time_line": [{"status": "Assigned", "time": "17:32:05"}]
}
```

**Calculation**:
- Department: FO
- Escalation Time: 2 minutes (from hierarchy)
- Assignment Time: 17:32:05
- Current Time: 17:32:30
- Elapsed: 25 seconds
- Remaining: 1 minute 35 seconds

### Scenario 3: Multi-Department Staff
**Staff Hierarchy**:
```json
{
  "hierarchy": [
    {"department": "EHK", "escalationTime": 1},
    {"department": "FO", "escalationTime": 2},
    {"department": "F&B", "escalationTime": 15}
  ]
}
```

**Stored Escalation Times**:
```dart
{
  "EHK": 1,
  "FO": 2,
  "F&B": 15
}
```

**Task Handling**:
- EHK task → 1 minute timer
- FO task → 2 minute timer
- F&B task → 15 minute timer

## Benefits

1. **✅ Accurate Timers**: Each department gets its appropriate escalation time
2. **✅ Dynamic**: No hardcoding - all values come from API
3. **✅ Scalable**: Works with any number of departments
4. **✅ Flexible**: Easy to add new departments without code changes
5. **✅ Multi-Department Support**: Staff with multiple departments can handle all task types correctly
6. **✅ Backward Compatible**: Falls back to legacy method if department not found

## Console Logs (for Debugging)

During login:
```
💾 Saved escalation time for EHK: 1 minutes
💾 Saved escalation time for FO: 2 minutes
✅ Saved all department escalation times: {EHK: 1, FO: 2}
```

During task timer calculation:
```
✅ Found escalation time for EHK: 1 minutes
⏱️ Task 1219 (EHK): Escalation in 1 min, Elapsed: 0 min, Remaining: 1 min
```

When department not found:
```
⚠️ No escalation time found for department: UNKNOWN, using fallback
```

## Testing Checklist

- [x] Login saves all department escalation times
- [x] EHK tasks use 1 minute timer
- [x] FO tasks use 2 minutes timer
- [x] Tasks without category fall back to default
- [x] Multi-department staff can handle all task types
- [x] Timers count down correctly
- [x] Console logs show correct department matching
- [x] No linter errors

## Files Modified

1. `lib/Services/local_storage_service.dart` - Added department escalation time methods
2. `lib/Screens/login_page.dart` - Save all department escalation times on login
3. `lib/Services/escalation_timer_service.dart` - Get task-specific escalation times

## Migration Notes

- **Backward Compatible**: Old code still works with fallback methods
- **No Breaking Changes**: Existing single-department staff continue to work
- **Automatic**: No manual data migration needed - updates on next login


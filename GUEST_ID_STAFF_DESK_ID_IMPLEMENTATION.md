# Guest ID and Staff Desk ID Implementation

## Overview
This document describes the implementation of `guest_id` and `staff_desk_id` fields in task update operations throughout the staff app. These fields are now included whenever tasks are updated from one status to another.

## Implementation Details

### Background
Based on the task data structure from the API response, each task contains:
- `guest_id`: The ID of the guest who created the task/order
- `staff_desk_id`: The desk/station ID associated with the staff member

These fields need to be sent back to the API whenever a task status is updated to maintain data consistency and traceability.

### Task Status Flow

The staff app handles the following task status transitions:

1. **Assigned → Processing** (Home Screen)
   - When staff accepts an assigned task
   - Updates status to "Processing"
   
2. **Processing → Completed** (Processing Task Screen)
   - When staff marks a task as completed
   - Updates status to "Completed" and sets `completed_time`

**Note:** The "Delivered" status is managed externally (likely by backend or another system) and is not updated by the staff app.

## Files Modified

### 1. `lib/Services/task_service.dart`

#### Updated Methods

##### `updateTaskStatus()`
Added two new optional parameters:
```dart
static Future<http.Response> updateTaskStatus({
  required int taskId,
  required String status,
  int? assignedStaffId,
  String? assignedStaffName,
  DateTime? dateTime,
  int? guestId,              // NEW
  String? staffDeskId,       // NEW
})
```

**Payload Structure:**
```json
{
  "payload": {
    "update_task": {
      "status": "Processing",
      "assigned_staff_id": 84,
      "assigned_staff_name": "Service Staff",
      "guest_id": 40557,
      "staff_desk_id": "DESK001"
    }
  }
}
```

##### `updateCompletedTaskStatus()`
Added two new optional parameters:
```dart
static Future<http.Response> updateCompletedTaskStatus({
  required int taskId,
  required String status,
  int? assignedStaffId,
  String? assignedStaffName,
  int? guestId,              // NEW
  String? staffDeskId,       // NEW
})
```

**Payload Structure:**
```json
{
  "payload": {
    "update_task": {
      "status": "Completed",
      "assigned_staff_id": 84,
      "assigned_staff_name": "Service Staff",
      "completed_time": "2025-10-10T12:43:11.131Z",
      "guest_id": 40557,
      "staff_desk_id": "DESK001"
    }
  }
}
```

### 2. `lib/Screens/home_screen.dart`

#### Assigned → Processing Update

**Location:** Line ~934-971 (Accept button handler)

**Changes:**
- Extracts `guest_id` from task data (handles both int and string formats)
- Extracts `staff_desk_id` from task data as string
- Passes both values to `updateTaskStatus()`

**Code:**
```dart
// Get guest_id and staff_desk_id from task
final int? guestId = tasks[index]['guest_id'] is int
    ? tasks[index]['guest_id'] as int
    : int.tryParse(tasks[index]['guest_id']?.toString() ?? '');
final String? staffDeskId = tasks[index]['staff_desk_id']?.toString();

final resp = await TaskService.updateTaskStatus(
  taskId: taskId,
  status: 'Processing',
  assignedStaffId: staffId,
  assignedStaffName: staffName,
  guestId: guestId,
  staffDeskId: staffDeskId,
);
```

### 3. `lib/Screens/processing_task_screen.dart`

#### Processing → Completed Update

**Location:** Line ~1220-1241 (Complete button handler)

**Changes:**
- Extracts `guest_id` from task data (handles both int and string formats)
- Extracts `staff_desk_id` from task data as string
- Passes both values to `updateCompletedTaskStatus()`

**Code:**
```dart
// Get guest_id and staff_desk_id from task
final int? guestId = tasks[index]['guest_id'] is int
    ? tasks[index]['guest_id'] as int
    : int.tryParse(tasks[index]['guest_id']?.toString() ?? '');
final String? staffDeskId = tasks[index]['staff_desk_id']?.toString();

final response = await TaskService.updateCompletedTaskStatus(
  taskId: taskId,
  status: 'Completed',
  assignedStaffId: staffId,
  assignedStaffName: staffName,
  guestId: guestId,
  staffDeskId: staffDeskId,
);
```

## Data Handling

### guest_id
- **Type:** Integer
- **Handling:** Safely parses from task data, supporting both int and string representations
- **Nullability:** Optional (sent only if present in task data)
- **Example:** `40557`

### staff_desk_id
- **Type:** String
- **Handling:** Extracted as string from task data
- **Nullability:** Optional (sent only if present in task data)
- **Example:** `"DESK001"` or any alphanumeric identifier

## API Integration

### Request Format
When updating task status, the API receives:

```json
{
  "domain_name": "example.com",
  "user_id": "user123",
  "payload": {
    "update_task": {
      "status": "Processing",
      "assigned_staff_id": 84,
      "assigned_staff_name": "Service Staff",
      "guest_id": 40557,
      "staff_desk_id": "DESK001"
    }
  },
  "extras": {
    "find": {"id": 236}
  }
}
```

### Data Source
Both `guest_id` and `staff_desk_id` are extracted from the task data returned by the "get all tasks" API endpoint:

```json
{
  "id": 236,
  "guest_id": 40557,
  "staff_desk_id": "DESK001",
  "room_no": "316",
  "status": "Assigned",
  // ... other fields
}
```

## Benefits

1. **Data Consistency:** Ensures guest and desk information is maintained throughout the task lifecycle
2. **Traceability:** Allows backend to track which guest's tasks are being processed and at which desk
3. **Reporting:** Enables better analytics on task completion by desk/station
4. **Flexibility:** Uses optional parameters, so updates work even if fields are missing
5. **Type Safety:** Properly handles different data types (int/string) for guest_id

## Testing Scenarios

1. **Normal Flow:**
   - Task with `guest_id` and `staff_desk_id` present
   - Both values should be sent to API

2. **Missing Fields:**
   - Task without `guest_id` or `staff_desk_id`
   - Update should still work (fields are optional)

3. **Type Variations:**
   - `guest_id` as integer: Should work directly
   - `guest_id` as string: Should be parsed to integer

4. **Status Transitions:**
   - Assigned → Processing: Both fields included
   - Processing → Completed: Both fields included

## Notes

- **No Static Values:** All values are dynamically extracted from task data from the API
- **Backward Compatible:** Optional parameters ensure existing functionality continues to work
- **Safe Parsing:** Includes error handling for type conversion of `guest_id`
- **Read-Only Screens:** Completed, Delivered, Scheduled, and Escalated task pages don't update status, so no changes needed there


# GuestEzee Staffs App — Backend and API Integration

How the Flutter app talks to GuestEzee APIs, auth, and third-party services.

---

## 1. Base configuration

Files: `lib/Config/primary_config.dart`, `lib/Config/api_end_points.dart`

| Key | Value |
|-----|--------|
| Domain | `https://www.guestezee.com` |
| Staging (commented) | `https://guestezee.ecbee.net` |
| `user_id` | `16` |

URL pattern:

```
{domainName}:{endpoint}
→ https://www.guestezee.com:3406/staff/getall
```

The 4-digit prefix is treated as a **port**, then the path.

No `.env` / flavors. Environment is a compile-time constant. Switch domain by editing `PrimaryConfigData.domainName`.

---

## 2. Request / response pattern

- Method: **POST**
- Header: `Content-Type: application/json; charset=UTF-8`
- Client: `package:http`
- No Bearer JWT on most calls. Login returns a session payload stored in Hive.

Typical body:

```json
{
  "domain_name": "https://www.guestezee.com",
  "user_id": 16,
  "extras": { "find": { }, "pagination": false },
  "payload": { }
}
```

Typical success:

```json
{
  "success": 1,
  "status_code": 200,
  "result": { "data": [ ] },
  "message": "..."
}
```

UI treats HTTP 200/201 then `success == 1`. Errors use `NetworkErrorMessage` instead of raw exceptions.

Multipart: image upload (`9104/imageupload/create`) from Settings / `const.dart`.

---

## 3. Authentication

### Login

1. Staff getall by `staff_employee_number` (uppercase Employee ID)
2. Check `is_staff_active` (fallback `is_active`)
3. Customer getall by `member_id` → `hotel_enabled`
4. POST `1215/login`  
   - `username`: `{employeeId}-{domainName}`  
   - `password`: PIN
5. Save response in Hive `authBox` (`user`, `isLoggedIn`, `rememberMe`)
6. Register FCM token via staff update
7. `StaffPresenceService.onLogin` (test push to other devices)

### Generate PIN / Forgot PIN

OTP send → OTP verify → staff update `pin`. Same hotel/staff-active gates as login.

### Session

Hive holds the user map. SharedPreferences `staff_is_logged_in` is synced for Android native FCM.

Logout: prune FCM tokens / availability, clear Hive, go to login.

Forced logout: staff missing or inactive, or hotel disabled (`HotelStatusService`).

---

## 4. Active endpoints

| Port/path | Used for |
|-----------|----------|
| `3406/staff/getall` | Lookup, session, manager check, desk staff list, ASAP poll |
| `3404/staff/update` | PIN, availability, FCM tokens, profile image |
| `1215/login` | Login |
| `8016/otp/send` | OTP |
| `8016/otp/verify` | OTP |
| `3411/task/getall` | All task lists + track by id |
| `3410/task/update` | Accept, complete, desk assign, times |
| `9526/customer/getall` | Hotel enabled, name, ASAP room range |
| `1210/appversion/getall` | Force update (`staff_android_app_version` / iOS field) |
| `9545/productreviews/getall` | Delivered ratings |
| `9104/imageupload/create` | Profile photo |
| `5621/api/payment/OrderNotification` | Token-check / presence push |

Defined but unused: `8845/belowstaffs/getall`.

---

## 5. Data flow (tasks)

```
Login user (Hive)
  → member_id + staff id
  → TaskService POST getall (status, assigned_staff_id, rooms, …)
  → Screen list (10s refresh)
  → Accept / Complete / Assign → TaskService update
  → TrackTaskPage reloads by task id
```

Desk assign: `assignTaskFromDesk` — self → Processing; other staff → Assigned.

Hotel rooms for ASAP: customer `room_range` + staff `hierarchy[].department`.

---

## 6. Third-party integrations

### Firebase Cloud Messaging

- Init: `firebase_options.dart` + `google-services.json` / `GoogleService-Info.plist`
- Project: `hospitalitynewsapp-f7968` (sender `945771911357`)
- Foreground: Dart `onMessage` (needs **data** payload on iOS: `title`, `body`, `task_id`)
- Background / killed: `firebaseMessagingBackgroundHandler` + Android `CustomFirebaseMessagingService`
- Tap: `onMessageOpenedApp`, `getInitialMessage`, Android `orderAlertTapped` extras → `TrackTaskPage`
- Token stored on staff record (`fcm_tokens` array)

Silent presence push: `data.testing = true` — no UI/sound.

### Local notifications / alarm

- `flutter_local_notifications`
- Android `OrderAlertService` (custom sound `res/raw/alarm.mp3`, vibration)
- iOS `alarm` package + `audioplayers` in foreground
- Permissions: notifications, (legacy) exact alarm on older Android

### OTP

Backend `8016` — email + SMS. App only sends recipient email/mobile and verifies `reference_id` + code.

### Image hosting

Upload API returns a URL; staff update stores it on the staff record.

### Store links (version gate)

- Play: `https://play.google.com/store/apps/details?id=com.guestezee.staff`
- App Store: `https://apps.apple.com/app/6758706838`

### Phone

High-priority screen may `tel:` the front desk number from hotel/task data.

---

## 7. Integration points by service class

| Class | APIs |
|-------|------|
| `StaffService` | 3406, 3404, 1215, 8016, 5621 |
| `TaskService` | 3411, 3410, 9545 |
| `CustomerService` | 9526 |
| `VersionService` | 1210 |
| Settings / `const.dart` | 9104 then 3404 |

No GraphQL. No REST GET list APIs — all POST find/update as above.

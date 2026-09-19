# GuestEzee Staffs App — Flutter Architecture

Simple overview of the Flutter mobile app: structure, modules, navigation, and state.

---

## 1. Product

StaffEzee is a hotel staff task app. Staff log in with Employee ID + PIN, receive assigned tasks, accept/process/complete them, and get FCM alerts.

Roles:

| Role | How decided | Home |
|------|-------------|------|
| Floor staff | Not desk, not manager | Bottom tabs (Assigned → Delivered) |
| Desk staff | `at_desk: true` | Same tabs + ASAP / Cancelled FABs + Assign |
| Manager | Staff getall finds others with `higher_level_hierarchy.parentId` = this staff hierarchy id | Escalated / high-priority list |

---

## 2. Project structure

```
lib/
  main.dart                 App entry, Firebase, session, version gate
  app_theme.dart            Theme
  const.dart                Shared app bar, logout, image upload
  firebase_options.dart     Firebase Android / iOS options
  Config/
    primary_config.dart     Base URL + user_id
    api_end_points.dart     API path/port constants
  Screens/                  Full pages
  Services/                 API, session, FCM, timers, storage
  Custom Widgets/           Navigation, gates, task UI pieces
android/                    Native Android (FCM alarm service)
ios/                        Native iOS (APNs, CocoaPods)
assets/                     Images, fonts, alarm sound
```

### Screens

| File | Module |
|------|--------|
| `login_page.dart` | Login |
| `registration_page.dart` | Generate PIN |
| `forgot_pin_page.dart` | Forgot PIN |
| `home_screen.dart` | Assigned tasks |
| `processing_task_screen.dart` | In-progress |
| `completed_task_page.dart` | Completed |
| `delivered_task_page.dart` | Delivered + ratings |
| `cancelled_task_page.dart` | Cancelled (desk) |
| `asap_task_page.dart` | ASAP board (desk) |
| `track_task_page.dart` | Task detail, Accept / Assign |
| `escalated_tasks_page.dart` | Manager home |
| `high_priority_tasks_page.dart` | High-priority escalations |
| `settings_page.dart` | Profile, logout, image |
| `scheduled_task_page.dart` | Present but not in nav |
| `static_content_page.dart` | Privacy / About |

### Services (major)

| Service | Role |
|---------|------|
| `staff_service.dart` | Staff getall/update, login, OTP, FCM token, desk/manager helpers |
| `task_service.dart` | Task getall/update, desk assign |
| `customer_service.dart` | Hotel getall (`hotel_enabled`, name, room range) |
| `local_storage_service.dart` | Hive session (`authBox`) |
| `hotel_status_service.dart` | Poll staff active + hotel enabled |
| `manager_level_service.dart` | Manager vs staff |
| `push_notification_service.dart` | FCM + local notifications + tap navigation |
| `escalation_timer_service.dart` | Accept / processing countdown |
| `alarm_service.dart` | Looping alarm (Android native + iOS Alarm) |
| `version_service.dart` | Force-update check |

### Native

- Android: `CustomFirebaseMessagingService`, `OrderAlertService` (foreground alarm), `AlarmServicePlugin`
- iOS: `AppDelegate.swift`, entitlements (`aps-environment`), background modes `remote-notification` + `audio`

---

## 3. Dependencies (pubspec)

App version: **1.0.19+41**  
Dart SDK: **^3.6.1**

| Package | Use |
|---------|-----|
| `http` | REST |
| `hive` / `hive_flutter` | Local session |
| `shared_preferences` | Login flag for native FCM |
| `flutter_riverpod` | Bottom nav index (+ some screens) |
| `firebase_core` / `firebase_messaging` | Push |
| `flutter_local_notifications` | Foreground banners |
| `alarm` / `audioplayers` / `vibration` | Alerts |
| `permission_handler` | Notifications / photos |
| `pinput` | OTP UI |
| `file_picker` | Profile image |
| `url_launcher` | Store / tel |
| `package_info_plus` | Current app version |
| `intl` | Time format |
| `shimmer` | Loading |

---

## 4. State management

There is **no global app store**. Mix of:

1. **Hive** — logged-in user, remember me, manager flag, hotel/staff flags  
2. **Riverpod** — `bottomNavIndexProvider`; some list pages are `ConsumerStatefulWidget`  
3. **Service singletons / ValueNotifiers** — `HotelStatusService`, `StaffService.roleRevision`, badge service  
4. **Widget `setState`** — most task lists poll every ~10s and rebuild locally  

Session poll (~1 min) refreshes staff getall + customer getall and can force logout or switch manager/staff home.

---

## 5. Navigation flow

```
App start
  → Version check
  → If rememberMe + logged in:
        manager → EscalatedTasksPage
        else    → NavigationPage (Assigned)
  → Else LoginPage

Login / Generate PIN / Forgot PIN
  → staff getall (is_staff_active)
  → customer getall (hotel_enabled)
  → login / OTP / PIN
  → FCM token update
  → NavigationPage or EscalatedTasksPage

NavigationPage tabs
  0 Assigned (HomeScreen)
  1 Processing
  2 Completed
  3 Delivered

From cards / FCM tap → TrackTaskPage(taskId)
Desk FABs → ASAP / Cancelled
Settings → profile, logout
HotelStatusGate wraps MaterialApp (deactivated hotel / staff)
```

No named routes. Navigation is `MaterialPageRoute` + global `navigatorKey` for FCM.

---

## 6. Overall technical architecture

```
UI (Screens / Widgets)
        ↓
Services (Staff / Task / Customer / FCM / Session)
        ↓
http POST  →  https://www.guestezee.com:{port}/{path}
        ↓
Hive session  +  Firebase Cloud Messaging
        ↓
Android OrderAlertService / iOS Alarm + system banner
```

Portrait only. Hotel access and staff active are enforced on login and while the session is open.

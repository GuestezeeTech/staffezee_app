# GuestEzee Staffs App — Android and iOS Build

Build, signing, store IDs, Firebase, and release steps.

---

## 1. App identity

| | Android | iOS |
|--|---------|-----|
| Display name | StaffEzee | StaffEzee |
| Application / Bundle ID | `com.guestezee.staff` | `com.guestezee.staff` |
| Gradle namespace | `com.example.guestezee_staffs_app` | — |
| Version | `1.0.19+41` (`pubspec.yaml`) | same (`FLUTTER_BUILD_NAME` / `NUMBER`) |
| Play / App Store | package `com.guestezee.staff` | App ID `6758706838` |

Test target bundle: `com.guestezee.staff.RunnerTests`.

---

## 2. Flutter / Dart

| Item | Value |
|------|--------|
| Dart SDK (pubspec) | `^3.6.1` |
| Local Flutter SDK (typical) | `android/local.properties` → `flutter.sdk` |
| Commands | `flutter clean` then `flutter pub get` before release |

Exact Flutter toolchain version is whatever is installed on the build machine (`flutter --version`). Constraint is Dart **3.6.1+**.

---

## 3. Android

### SDK / Gradle

| Item | Value |
|------|--------|
| Gradle | **8.10.2** (`gradle-wrapper.properties`) |
| Android Gradle Plugin | **8.7.0** |
| Kotlin | **2.2.0** |
| Google Services plugin | **4.4.0** |
| compileSdk / minSdk / targetSdk | Flutter defaults (`flutter.compileSdkVersion` etc.) |
| Java | **11** |
| NDK | **27.0.12077973** |
| AndroidX | yes |

### Build types

- **Debug** — default debug signing, `flutter run` / `flutter build apk --debug`
- **Release** — `signingConfigs.release`, minify/shrink currently **off**
- **Profile** — Flutter profile
- **No product flavors** (no staging/prod Gradle flavors)

### Signing

Files:

- Keystore: `android/app/key.jks`
- Template: `android/key.properties.template`
- Local secrets: `android/key.properties` (gitignored by `android/.gitignore`; copy from template)

Template fields:

```
storePassword=...
keyPassword=...
keyAlias=your_key_alias
storeFile=app/key.jks
```

`build.gradle.kts` falls back to `key.jks` + password `guestezee` if `key.properties` is missing.

`android/.gitignore` ignores `*.jks` / `key.properties`. Force-add the jks only if the team wants it in git.

### APK / AAB

```bash
flutter clean
flutter pub get
flutter build apk --release          # APK
flutter build appbundle --release    # Play Store AAB
```

Outputs:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

### Google Play

1. Increment `version:` in `pubspec.yaml` (especially `+build` / versionCode).
2. Build AAB.
3. Play Console → app `com.guestezee.staff` → Production (or testing track) → upload AAB.
4. Keep the same upload keystore for all updates.

Also see `PLAY_CONSOLE_RELEASE_GUIDE.md` / `RELEASE_QUICK_START.md`.

### Android extras

- `google-services.json` (root + `android/app/`)
- Permissions: INTERNET, POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK
- `allowBackup=false`, `usesCleartextTraffic=false`
- Firebase Messaging + WorkManager in `app/build.gradle.kts`

---

## 4. iOS

### Xcode / CocoaPods

| Item | Value |
|------|--------|
| Platform / deployment target | **iOS 15.0** (`Podfile` + `IPHONEOS_DEPLOYMENT_TARGET`) |
| CocoaPods | `ios/Podfile`, `use_frameworks!`, stats disabled |
| Workspace | `ios/Runner.xcworkspace` |
| Configurations | Debug → debug; Profile/Release → release |
| Team | `ZC2T745A5Z` |
| Signing | Automatic, `iPhone Developer` |
| Entitlements | `Runner/Runner.entitlements` — `aps-environment` = **development** (switch to `production` for App Store push) |
| Background | `remote-notification`, `audio` |

After `flutter pub get`:

```bash
cd ios && pod install && cd ..
```

### IPA

```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

Or archive in Xcode: open `ios/Runner.xcworkspace` → Product → Archive → Distribute.

Output: `build/ios/ipa/*.ipa`

### App Store

1. Increment `pubspec.yaml` version.
2. Archive / `flutter build ipa`.
3. Upload via Xcode Organizer or Transporter.
4. App Store Connect app for bundle `com.guestezee.staff`.
5. Need Apple Distribution cert + App Store provisioning (Automatic signing uses team `ZC2T745A5Z`).
6. For production FCM, set `aps-environment` to `production` and use a production APNs key/cert in Firebase.

---

## 5. Environments / API config

No Dart-define flavors.

| Env | How |
|-----|-----|
| Production | `PrimaryConfigData.domainName = https://www.guestezee.com` |
| Staging | Uncomment `https://guestezee.ecbee.net` in `primary_config.dart` and rebuild |

`user_id` is always `16`.

---

## 6. Firebase / FCM

| Item | Value |
|------|--------|
| Project | `hospitalitynewsapp-f7968` |
| Sender ID | `945771911357` |
| Android app id | `1:945771911357:android:bd81263d8355f20c773fd4` |
| iOS app id | `1:945771911357:ios:f712455b48e3705d773fd4` |
| Dart | `lib/firebase_options.dart` |
| Android | `android/app/google-services.json` |
| iOS | `ios/Runner/GoogleService-Info.plist` |

FCM payload for iOS foreground must include `data` (`title`, `body`, `task_id`).

---

## 7. Certificates and other build files

| Asset | Where / notes |
|-------|----------------|
| Android keystore | `android/app/key.jks` |
| key.properties | Local, not in git by default |
| Google services | `google-services.json`, `GoogleService-Info.plist` |
| iOS signing | Apple Developer team `ZC2T745A5Z`, Automatic |
| APNs | Firebase iOS app + entitlements `aps-environment` |
| Alarm sound | `assets/audio/alarm.mp3`, Android `res/raw/alarm.mp3` |
| Icons | `flutter_launcher_icons` from `assets/images/staff_logo.png` |

---

## 8. Debug vs production (summary)

| | Debug | Production release |
|--|-------|-------------------|
| Command | `flutter run` / `--debug` | `flutter build appbundle` / `ipa --release` |
| API | Same production URL unless `primary_config` edited | Same |
| Android sign | Debug keystore | `key.jks` + `key.properties` |
| iOS sign | Development / Automatic | Distribution + App Store profile |
| Push | Dev APNs (`development` entitlement) | Production APNs |
| Minify | Off | Off (configured but disabled) |

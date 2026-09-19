# Google Play Console Release Guide

This guide walks you through all the steps needed to build and publish your GuestEzee Staff app to Google Play Console.

## 📋 Pre-Release Checklist

### ✅ Completed Changes
- [x] Updated application ID to `com.guestezee.staff`
- [x] Fixed namespace to match application ID
- [x] Changed app label to "GuestEzee Staff" (user-friendly name)
- [x] Configured ProGuard/R8 for code shrinking and obfuscation
- [x] Added security settings (disabled cleartext traffic, disabled backup)
- [x] Set up signing configuration

---

## 🔑 Step 1: Create Your Upload Keystore

A keystore is required to sign your app for release. **Keep this file safe!** You'll need it for all future updates.

### Generate Keystore (Windows PowerShell):

```powershell
cd F:\guestezee_staffs_app\android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### During keystore generation, you'll be asked:

1. **Enter keystore password**: Choose a strong password (remember this!)
2. **Re-enter keystore password**: Confirm your password
3. **Enter key password**: Can be same as keystore password (recommended)
4. **What is your first and last name?**: Your name or company name
5. **What is the name of your organizational unit?**: Your department/team
6. **What is the name of your organization?**: GuestEzee
7. **What is the name of your City or Locality?**: Your city
8. **What is the name of your State or Province?**: Your state
9. **What is the two-letter country code?**: Your country code (e.g., US, IN)

### Important Notes:
- **NEVER commit the keystore file to version control**
- **Store it in a secure location with backups**
- If you lose this file, you cannot update your app on Play Store!

---

## 🔐 Step 2: Configure Signing

### Create `key.properties` file:

1. Copy the template:
```powershell
cd F:\guestezee_staffs_app\android
Copy-Item key.properties.template key.properties
```

2. Edit `android/key.properties` with your actual values:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
```

Replace:
- `YOUR_KEYSTORE_PASSWORD`: Password you entered when creating keystore
- `YOUR_KEY_PASSWORD`: Key password (usually same as keystore password)

### Add to .gitignore:

Ensure these lines are in your `.gitignore` file (create one if it doesn't exist):
```
# Android signing
**/android/key.properties
**/android/upload-keystore.jks
**/android/*.jks
**/android/*.keystore
```

---

## 📝 Step 3: Update Version Number

Before each release, update the version in `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

Format: `MAJOR.MINOR.PATCH+BUILD_NUMBER`

- **1.0.0**: Version name (shown to users)
- **+1**: Build number (must be unique and increment for each upload)

**For subsequent releases:**
- Bug fixes: `1.0.1+2`
- New features: `1.1.0+2`
- Major changes: `2.0.0+2`

**Note**: Build number (+1, +2, +3) must always increase and be unique!

---

## 🏗️ Step 4: Build Release AAB

### Clean previous builds:
```powershell
flutter clean
flutter pub get
```

### Build the Android App Bundle (AAB):
```powershell
flutter build appbundle --release
```

### Build output location:
```
build\app\outputs\bundle\release\app-release.aab
```

### Verify the build:
- File size should be reasonable (typically 15-50 MB for most apps)
- Check that no errors occurred during build

### Optional - Build APK for testing:
```powershell
flutter build apk --release
```
APK location: `build\app\outputs\apk\release\app-release.apk`

---

## 🎮 Step 5: Upload to Google Play Console

### First Time Setup:

1. **Go to Google Play Console**: https://play.google.com/console
2. **Create New App**:
   - App name: `GuestEzee Staff`
   - Default language: Choose your language
   - App or game: App
   - Free or paid: Choose based on your model

3. **Fill Required Information**:

   #### App Access:
   - Declare if special access is needed
   - Provide test login credentials if app requires login

   #### Ads:
   - Select "No" if you don't show ads, "Yes" if you do

   #### Content Rating:
   - Complete the questionnaire
   - This determines age ratings (Everyone, Teen, etc.)

   #### Target Audience:
   - Select age groups your app targets
   - Complete all questions

   #### News App:
   - Select "No" unless this is a news app

   #### COVID-19 Contact Tracing:
   - Select "No" unless applicable

   #### Data Safety:
   - **IMPORTANT**: Declare what data you collect
   - Based on your app:
     - Personal info (name, phone number)
     - Location data (if you track staff location)
     - Device or other IDs (for notifications)
   - Specify how data is used (app functionality, analytics, etc.)
   - Specify if data is shared with third parties
   - Specify your privacy policy URL

   #### Government Apps:
   - Select applicable option

### Privacy Policy:
- **Required for most apps**
- Must be hosted on a publicly accessible URL
- Should explain: what data you collect, why, how it's used, and how users can delete it

---

## 📤 Step 6: Upload Your Release

### Create a Production Release:

1. **Navigate to**: Production → Releases → Create new release

2. **Upload the AAB**:
   - Click "Upload"
   - Select `build\app\outputs\bundle\release\app-release.aab`
   - Wait for upload and processing

3. **Release Name**: Auto-filled from version (1.0.0)

4. **Release Notes**: Add what's new
   ```
   Initial release of GuestEzee Staff app
   - Manage guest requests efficiently
   - Real-time notifications
   - Staff task management
   - And more...
   ```

5. **Review and rollout**:
   - Review all information
   - Click "Save" then "Review release"
   - Click "Start rollout to Production"

---

## 🧪 Step 7: Testing Before Production (Recommended)

### Internal Testing:
1. **Go to**: Testing → Internal testing → Create new release
2. Upload AAB
3. Add testers (email addresses)
4. Testers receive link to install from Play Store
5. Test thoroughly before production

### Closed/Open Testing:
- **Closed testing**: Invite specific testers
- **Open testing**: Anyone can join and test
- Use for beta testing with larger audience

---

## ⚙️ Step 8: Additional Configurations

### Store Listing:

1. **App Details**:
   - App name: `GuestEzee Staff`
   - Short description: (80 chars) Brief description
   - Full description: (4000 chars) Detailed description

2. **Graphics**:
   - **App icon**: 512 x 512 px PNG (high-res icon)
   - **Feature graphic**: 1024 x 500 px JPG/PNG (required)
   - **Phone screenshots**: At least 2 (up to 8)
     - Portrait: 16:9 ratio
     - Landscape: 16:9 ratio
   - **Tablet screenshots**: Optional but recommended
   - **Video**: YouTube URL (optional)

3. **Categorization**:
   - App category: Business or Productivity
   - Tags: Add relevant tags

4. **Contact Details**:
   - Email: Support email address
   - Phone: Optional
   - Website: Optional

5. **Privacy Policy**:
   - URL to your privacy policy (required)

---

## 🔄 Future Updates

### To release an update:

1. **Update version** in `pubspec.yaml`:
   ```yaml
   version: 1.0.1+2  # Increment build number!
   ```

2. **Build new AAB**:
   ```powershell
   flutter clean
   flutter pub get
   flutter build appbundle --release
   ```

3. **Upload to Play Console**:
   - Production → Create new release
   - Upload new AAB
   - Add release notes
   - Review and rollout

---

## 🛠️ Technical Details

### What Was Changed for Release:

#### `android/app/build.gradle.kts`:
- ✅ Fixed namespace from `com.example.guestezee_staffs_app` to `com.guestezee.staff`
- ✅ Added keystore properties loading
- ✅ Created release signing configuration
- ✅ Enabled code shrinking (`isMinifyEnabled = true`)
- ✅ Enabled resource shrinking (`isShrinkResources = true`)
- ✅ Added ProGuard rules

#### `android/app/src/main/AndroidManifest.xml`:
- ✅ Changed label to "GuestEzee Staff"
- ✅ Added `android:allowBackup="false"` (security)
- ✅ Added `android:usesCleartextTraffic="false"` (security)

#### New Files Created:
- ✅ `android/app/proguard-rules.pro` - Code obfuscation rules
- ✅ `android/key.properties.template` - Template for signing config
- ✅ `PLAY_CONSOLE_RELEASE_GUIDE.md` - This guide

---

## 🚨 Common Issues & Solutions

### Issue: "Keystore not found"
**Solution**: Ensure `upload-keystore.jks` is in the `android` directory and path in `key.properties` is correct.

### Issue: "Version code has already been used"
**Solution**: Increment the build number in `pubspec.yaml` (e.g., from +1 to +2).

### Issue: Build fails with ProGuard errors
**Solution**: Check `proguard-rules.pro` and add keep rules for any missing classes shown in error.

### Issue: "Google Play signing not configured"
**Solution**: Enable Google Play App Signing in Play Console (recommended). Upload your upload certificate.

### Issue: App crashes in release but not debug
**Solution**: Usually ProGuard issue. Check stack trace and add keep rules for the affected classes.

---

## 📱 App Signing by Google Play (Recommended)

Google Play App Signing protects your app signing key and makes updates more secure.

### Enable App Signing:

1. **During first upload**, Play Console will prompt you
2. **Choose**: "Let Google manage my app signing key"
3. Google will:
   - Generate a new app signing key
   - Re-sign your AAB with it
   - Keep the signing key secure
   - You only need your upload key for future updates

### Benefits:
- Lost upload key? Google can reset it
- More secure key management
- Smaller downloads (Google optimizes for each device)

---

## ✅ Pre-Submission Checklist

Before submitting to production:

- [ ] Tested app thoroughly on multiple devices
- [ ] Verified all features work correctly
- [ ] No crashes or major bugs
- [ ] Notifications work properly
- [ ] All permissions are properly requested
- [ ] Privacy policy is published and URL is correct
- [ ] Screenshots and graphics are ready
- [ ] Store listing is complete
- [ ] Release notes are written
- [ ] Version number is updated
- [ ] AAB is signed with release keystore
- [ ] Keystore and key.properties are backed up securely

---

## 🎉 After Submission

### Review Process:
- Google reviews your app (usually 1-3 days)
- You'll receive an email when review is complete
- If approved, app goes live automatically
- If rejected, you'll receive reasons and can fix and resubmit

### Monitor Your App:
- Check crash reports in Play Console
- Respond to user reviews
- Monitor ratings
- Track installations and usage

---

## 📞 Support & Resources

- **Flutter Build Docs**: https://docs.flutter.dev/deployment/android
- **Play Console Help**: https://support.google.com/googleplay/android-developer
- **Android App Signing**: https://developer.android.com/studio/publish/app-signing

---

## 🔒 Security Notes

**NEVER commit these to version control:**
- `android/key.properties`
- `android/upload-keystore.jks`
- `android/*.jks`
- `android/*.keystore`

**Always keep secure backups of:**
- Upload keystore file
- Keystore passwords
- Key alias and password

**Best Practices:**
- Use strong, unique passwords for keystore
- Store keystore in secure, backed-up location (consider password manager or secure cloud storage)
- Keep copies in multiple secure locations
- Document keystore details securely

---

## 🎯 Quick Reference Commands

```powershell
# Clean and get dependencies
flutter clean
flutter pub get

# Build release AAB (for Play Store)
flutter build appbundle --release

# Build release APK (for testing)
flutter build apk --release

# Check build size
flutter build appbundle --release --target-platform android-arm,android-arm64 --analyze-size

# Run in release mode (for testing)
flutter run --release
```

---

**Good luck with your release! 🚀**

If you encounter any issues, check the Common Issues section above or refer to the official Flutter and Google Play documentation.


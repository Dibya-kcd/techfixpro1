# TechFix Pro v4 — Setup Guide

## 1. Install Dependencies
```bash
flutter pub get
```

## 2. Camera & Storage Permissions

### Android — android/app/src/main/AndroidManifest.xml
Add inside <manifest> tag:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

### iOS — ios/Runner/Info.plist
Add inside <dict>:
```xml
<key>NSCameraUsageDescription</key>
<string>TechFix Pro uses camera to photograph devices for repair records</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>TechFix Pro reads photos to attach to repair jobs</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>TechFix Pro saves repair photos to your library</string>
```

## 3. Run the App
```bash
flutter run
```

## 4. Features in this version
- ✅ Full CRUD: Jobs, Customers, Products, Technicians
- ✅ Camera + Gallery photo capture (real image_picker integration)
- ✅ Settings — all 20 sub-pages fully working with save buttons
- ✅ Hold / Cancel / Resume / Re-open workflow with reasons
- ✅ Notify customer via WhatsApp / SMS / Email
- ✅ POS system with cart
- ✅ Reports with charts
- ✅ Riverpod state management throughout

## 5. Auth (see TechFix_Auth_DB_Schema.docx)
Add to pubspec.yaml:
- firebase_core: ^3.1.0
- firebase_auth: ^5.1.0
- cloud_firestore: ^5.1.0
- flutter_secure_storage: ^9.0.0
- local_auth: ^2.2.0

# Presensi (Flutter)

Employee attendance app: email/password + Google sign-in (Firebase Auth),
check-in/out with GPS location (Firestore), and a map of recorded locations.

Native Android port: see `presensi-android` (separate repo/project).

## Prerequisites

- Flutter SDK (stable)
- Firebase CLI logged in (`firebase login`)
- An Android device or emulator with Google Play Services

## Firebase setup (required — config files are gitignored)

These files are **not** in git (they contain API keys). Regenerate them with:

```bash
flutterfire configure --project=presensi-diengcyber
```

This creates `lib/firebase_options.dart`, `android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist`, and `macos/Runner/GoogleService-Info.plist`.

Or download manually from the Firebase console
(Project settings → Your apps) into the same paths, then run
`flutterfire configure` once to generate `lib/firebase_options.dart`.

Also required in the Firebase console:

- **Authentication → Sign-in method**: enable Email/Password **and** Google
- **Google sign-in**: copy the OAuth **web client ID** if a native client needs it
- **Debug SHA-1** registered for each Android app, otherwise Google sign-in
  fails (get it via
  `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`,
  register with
  `firebase apps:android:sha:create <APP_ID> <SHA1> --project presensi-diengcyber`)

## Run

```bash
flutter pub get
flutter run --debug
```

On Xiaomi/MIUI phones: enable **Install via USB** and
**USB debugging (Security settings)** in Developer options, and install with
`adb install -r --user 0 <apk>` so the app lands on the main profile
(not Second Space).

## Release APK (for GitHub Releases, not Play Store)

Most phones use the `arm64` APK. Upload the `.sha1` files alongside so
downloaders can verify with `sha1sum -c`.

## Notes

- Firestore collection `attendance` is shared with the native app:
  fields `employeeId`, `type` (`masuk`/`keluar`), `lat`, `lng`, `timestamp`.
- Map tiles: Esri World Street Map (key-free). OSM's own tile servers block
  in-app usage and CARTO now requires an API key.
- Firebase API keys in the config files are public client identifiers by
  design — protect them with key restrictions in Google Cloud Console
  (Android/iOS app + API restrictions), not by hiding them.

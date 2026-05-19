# OAuth & Password Recovery E2E Checklist

This checklist helps verify Google/Facebook OAuth flows and the password recovery flow on web and mobile.

## Preparation
- Ensure Supabase OAuth providers (Google, Facebook) are configured with correct redirect URLs:
  - Web: `https://<your-app-origin>` (e.g. `https://app.example.com` or `http://localhost:8080`)
  - Android/iOS: `io.supabase.flutter://login-callback`
- Build the app for web and mobile or run in debug mode:
  - Web: `flutter run -d chrome` (or `-d web-server`)
  - Android emulator: `flutter run -d emulator-5554`
  - iOS simulator: `flutter run -d <simulator>`

## Web: Google sign-in
1. Open an incognito/private window to avoid existing sessions.
2. Run `flutter run -d chrome` and open the app.
3. Click the Google sign-in button — the OAuth provider should open.
4. Complete provider login; after success you should be redirected back to your app origin with a fragment or query (Supabase may return `#access_token=...` or `?code=...`).
5. Confirm the app navigates to the dashboard (not to sign-in).
6. Confirm the browser URL no longer contains the fragment (the fragment should be cleared by `clearUrlFragment()`).
7. If the app didn't capture the session, check browser console/network for redirect URLs and look for `getSessionFromUrl` calls in logs.

## Web: Facebook sign-in
Follow the same flow as Google; ensure Facebook app settings have the same redirect origin.

## Mobile (Android/iOS): Google & Facebook
1. Start the app on a device/emulator.
2. Tap the provider button; complete the provider flow in the browser or SFSafariViewController.
3. Provider should redirect to the deep link `io.supabase.flutter://login-callback#...` (or `?code=...`).
4. Confirm the app receives the deep link and navigates to the dashboard.
5. To simulate a callback manually on Android use adb:

```bash
adb shell am start -a android.intent.action.VIEW -d "io.supabase.flutter://login-callback#access_token=TEST&token_type=bearer" \
  com.example.yourapp
```

On iOS simulator:

```bash
xcrun simctl openurl booted "io.supabase.flutter://login-callback#access_token=TEST"
```

## Password recovery flow
1. In-app, request password reset for a test account (`Forgot Password`).
2. Inspect the email received (or use Supabase auth admin to view the generated link).
3. Click the reset link from the device/browser running the app.
4. Confirm the app opens the reset page and that `getSessionFromUrl` provides a recovery session.
5. Complete the reset; confirm `updateUser` runs and the user is signed in and navigated to the dashboard.

## Troubleshooting
- If the fragment arrives but `getSessionFromUrl` fails, log the full redirect URL and confirm it's being normalized (fragment → query).
- On web, check that `PathUrlStrategy()` is set (so the app does not treat fragments as routing changes) and that `clearUrlFragment()` runs after successful session application.
- For mobile, ensure Supabase `authCallbackUrlHostname` is `login-callback` and app link/intent filters are configured in `AndroidManifest.xml` / iOS `Info.plist`.

## Quick debug commands
- Run web locally: `flutter run -d chrome`
- Run android emulator: `flutter run -d emulator-5554`
- Simulate deep link (Android): see `adb` command above
- Simulate deep link (iOS simulator): see `xcrun` command above

## Expected outcomes
- Successful OAuth redirect is consumed by the app and user session is applied.
- Browser URL fragment is cleared after session application on web.
- Splash navigation does not double-route; app navigates exactly once to the dashboard.

# Tatis Barbershop

This repository contains the full Tatis Barbershop stack:

- `mobile-app/` - Flutter client for web, Android, and iOS
- `api/` - PHP backend endpoints used by the app
- `database/` - schema and seed assets
- `web-admin/` - browser-based admin and receptionist UI
- `scripts/` - helper utilities used by the project

## What You Need

Install these before working on the project:

- Flutter SDK 3.5.x or compatible with the `pubspec.yaml` constraint
- Dart 3.5.x (bundled with Flutter)
- Git
- A PHP runtime such as XAMPP, WAMP, or Apache + PHP 8.x
- A database server required by your backend environment
- Chrome for web testing, plus Android Studio or an Android emulator if you plan to run mobile builds

## Project Setup

### 1. Clone the repository

```bash
git clone https://github.com/BugSlayerRien/barberyanitatis.git
cd barberyanitatis/tatis_barbershop
```

### 2. Set up the backend

The Flutter app calls PHP endpoints under `api/`. The default local URLs in the app point to:

- Web: `http://localhost/barberyanitatis/tatis_barbershop/api`
- Android emulator: `http://10.0.2.2/barberyanitatis/tatis_barbershop/api`

To make that work locally:

1. Serve the `tatis_barbershop/` folder through Apache or your local PHP server.
2. Make sure the `api/` folder is reachable at the URL above.
3. Configure database connection variables for the backend environment.

The backend uses a PDO helper in `api/db.php`. Depending on the branch/environment, it may read connection values from environment variables such as:

- `DB_URL` or `DATABASE_URL`
- `DB_DSN`
- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASS`
- `DB_SSLMODE`
- `DB_HOSTADDR`

If you are deploying locally, define the values that match your database server and confirm the schema matches the database engine you are using.

### 3. Set up the Flutter app

From `tatis_barbershop/mobile-app/`:

```bash
flutter pub get
```

Useful validation commands:

```bash
flutter analyze
flutter test
```

Run the app with one of these targets:

```bash
flutter run -d chrome
flutter run -d android
```

If you need to override the backend URL, pass `API_BASE_URL` at build time:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost/barberyanitatis/tatis_barbershop/api
```

## Flutter Dependencies

The app already declares its dependencies in `mobile-app/pubspec.yaml`. The main packages currently used are:

- `camera`
- `camera_web`
- `image_picker`
- `google_sign_in`
- `google_fonts`
- `http`
- `google_generative_ai`
- `google_mlkit_face_detection`
- `model_viewer_plus`
- `shared_preferences`

Assets and fonts are already configured in `pubspec.yaml`:

- `assets/images/`
- `assets/images/overlays/`
- `assets/models/`
- `assets/fonts/`

## App Behavior Notes

- `mobile-app/lib/user/api_config.dart` controls the API base URL.
- `mobile-app/lib/main.dart` boots the app and goes directly to the splash screen.
- Firebase is not currently initialized in the source tree, so there is no Firebase setup step unless you add it later.
- `google_sign_in` is present, but that is not the same as a full Firebase installation.

## Suggested Developer Workflow

1. Create a feature branch.
2. Make your Flutter or backend changes.
3. Run `flutter analyze` and any relevant tests.
4. Verify the API endpoints still respond against your local server.
5. Open a pull request back into `develop`.

## Notes For New Developers

- If the app cannot reach the backend, first check the `API_BASE_URL` value and your local Apache/PHP path.
- If images fail to load on web, confirm the backend image proxy endpoint is reachable.
- If you are modifying database code, make sure the backend DSN variables and schema match the server you are running.

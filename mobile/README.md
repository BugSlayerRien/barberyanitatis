# Mobile App (Flutter)

Customer-facing mobile application for the Barbershop Management System.

## Overview

Flutter-based mobile app for customers to:
- Get AI-powered hairstyle recommendations
- Book appointments with stylists
- View service catalog
- Manage appointments
- Leave reviews

## Features

### AI Hairstyle Recommendations
- Upload selfie for face analysis
- Get personalized hairstyle suggestions
- View before/after visualizations
- Save favorite styles

### Appointment Booking
- Browse available stylists
- Check real-time availability
- Select services and time slots
- Receive booking confirmations

### User Profile
- Manage personal information
- View appointment history
- Track loyalty points
- Update preferences

### Reviews & Ratings
- Rate completed services
- Leave detailed reviews
- View stylist ratings

## Tech Stack

- **Framework**: Flutter 3.0+
- **State Management**: Provider / Riverpod
- **HTTP Client**: Dio
- **Local Storage**: Hive / SharedPreferences
- **Image Processing**: image_picker, image_cropper
- **UI Components**: Material Design 3

## Project Structure

```
mobile/
├── lib/
│   ├── screens/          # App screens
│   │   ├── home/
│   │   ├── appointments/
│   │   ├── ai_recommendations/
│   │   ├── profile/
│   │   └── auth/
│   ├── widgets/          # Reusable widgets
│   ├── services/         # API services
│   ├── models/           # Data models
│   ├── utils/            # Helper functions
│   └── main.dart
├── assets/
│   ├── images/
│   └── fonts/
├── test/
└── pubspec.yaml
```

## Setup

### Prerequisites

- Flutter SDK 3.0+
- Dart 3.0+
- Android Studio / Xcode
- Android SDK / iOS SDK

### Installation

```bash
cd mobile

# Get dependencies
flutter pub get

# Run the app
flutter run
```

### Configuration

Create `lib/config/app_config.dart`:

```dart
class AppConfig {
  static const String apiBaseUrl = 'http://localhost:3000/api';
  static const String aiServiceUrl = 'http://localhost:5000/api';
  static const String appName = 'Barbershop';
}
```

## Screens

### 1. Authentication
- Login
- Register
- Forgot Password

### 2. Home
- Featured services
- Quick booking
- AI recommendation shortcut
- Upcoming appointments

### 3. AI Recommendations
- Camera/Gallery image upload
- Face analysis results
- Hairstyle suggestions
- Save favorites

### 4. Stylists
- Browse stylists
- View profiles and ratings
- Check availability
- Filter by specialization

### 5. Services
- Service catalog
- Detailed descriptions
- Pricing information
- Duration estimates

### 6. Appointments
- Create new booking
- View upcoming appointments
- Appointment history
- Modify/Cancel bookings

### 7. Profile
- Personal information
- Appointment history
- Loyalty points
- Preferences
- Settings

## Key Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  provider: ^6.1.1
  
  # Networking
  dio: ^5.3.3
  
  # Local Storage
  shared_preferences: ^2.2.2
  hive: ^2.2.3
  
  # Image Handling
  image_picker: ^1.0.4
  image_cropper: ^5.0.0
  cached_network_image: ^3.3.0
  
  # UI Components
  flutter_svg: ^2.0.9
  shimmer: ^3.0.0
  
  # Date/Time
  intl: ^0.18.1
  table_calendar: ^3.0.9
  
  # Authentication
  flutter_secure_storage: ^9.0.0
```

## API Integration

Services are organized by feature:

```dart
// lib/services/api_service.dart
class ApiService {
  final Dio _dio;
  
  Future<List<Stylist>> getStylists() async {
    final response = await _dio.get('/stylists');
    return response.data['data'];
  }
  
  Future<Appointment> createAppointment(AppointmentData data) async {
    final response = await _dio.post('/appointments', data: data);
    return Appointment.fromJson(response.data['data']);
  }
}

// lib/services/ai_service.dart
class AIService {
  Future<FaceAnalysis> analyzeFace(File image) async {
    // Call AI service for face analysis
  }
  
  Future<List<Recommendation>> getRecommendations(FaceShape shape) async {
    // Get hairstyle recommendations
  }
}
```

## State Management

Using Provider for state management:

```dart
class AppointmentProvider extends ChangeNotifier {
  List<Appointment> _appointments = [];
  
  Future<void> fetchAppointments() async {
    _appointments = await apiService.getAppointments();
    notifyListeners();
  }
  
  Future<void> createAppointment(AppointmentData data) async {
    final appointment = await apiService.createAppointment(data);
    _appointments.add(appointment);
    notifyListeners();
  }
}
```

## Testing

```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test

# Run with coverage
flutter test --coverage
```

## Build

### Android
```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## Design System

- **Primary Color**: Custom barbershop theme
- **Typography**: Material Design 3
- **Spacing**: 8px grid system
- **Icons**: Material Icons + Custom

## Performance

- Lazy loading for lists
- Image caching
- API response caching
- Offline support with local storage

## License

MIT

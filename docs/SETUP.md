# Enterprise Biometric Auth System — Setup Guide

## Prerequisites
- Flutter SDK 3.16.0+
- Dart SDK 3.2.0+
- Android Studio / VS Code with Flutter plugin
- Xcode 15+ (for iOS)
- Real device for biometric testing (simulators may have limited support)

## Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/AvinashK123-A/flutter-biometric-auth-system.git
cd flutter-biometric-auth-system
```

### 2. Environment Setup
```bash
cp .env.example .env
```

### 3. Install Dependencies
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

## Platform-Specific Setup

### Android Biometric Setup
The project requires Android 6.0 (API 23) or higher for fingerprint, Android 9.0+ for BiometricPrompt.
- Permissions already configured in AndroidManifest.xml
- BiometricManager used for capability checking
- Encrypted SharedPreferences for secure token storage

### iOS Face ID / Touch ID Setup
- NSFaceIDUsageDescription already in Info.plist
- LAContext used for local authentication
- Keychain used for secure token storage
- Requires device with Touch ID or Face ID

## Security Features

### Jailbreak / Root Detection
The SecurityManager class detects:
- iOS: Cydia, unusual file paths, sandbox violations
- Android: su binary, build tags, test-keys
Configure behavior in lib/core/security/security_manager.dart

### Session Management
- Default session duration: 30 minutes
- Configurable in BiometricService
- Auto-lock on app background

### Secure Storage
- iOS: Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
- Android: EncryptedSharedPreferences (AES-256)
- Never stored in plain text

### Failed Attempt Lockout
- 5 failed attempts trigger account lock
- 15-minute lockout duration
- Configurable in AuthController

## Run Configurations
```bash
# Development (with biometric testing)
flutter run --flavor dev -t lib/main_dev.dart

# Production
flutter run --flavor prod -t lib/main_prod.dart
```

## Testing Biometrics
```bash
# On iOS Simulator: Hardware > Face ID > Enrolled
# On Android Emulator: Settings > Security > Fingerprint

# Run tests
flutter test test/unit/
```

## Project Structure
```
lib/
├── core/
│   ├── security/       # Jailbreak detection, SecurityManager
│   ├── services/       # BiometricService with LocalAuth
│   ├── storage/        # Secure encrypted storage
│   ├── di/             # GetX dependency injection
│   ├── routes/         # GetX routing with auth guards
│   └── theme/          # Material 3 dark/light theme
├── features/
│   ├── auth/           # Login, biometric auth, session
│   ├── home/           # Protected dashboard
│   ├── settings/       # Biometric enable/disable
│   └── profile/        # User profile with security info
└── main.dart
```

## Architecture
- **Pattern**: Clean Architecture + Feature-first
- **State Management**: GetX
- **Authentication**: local_auth (biometric) + JWT
- **Storage**: flutter_secure_storage (encrypted)
- **Security**: Custom jailbreak detection

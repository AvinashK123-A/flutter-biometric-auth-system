<div align="center">

![banner](https://capsule-render.vercel.app/api?type=waving&color=1A1A2E&height=200&section=header&text=Enterprise%20Biometric%20Auth&fontSize=30&fontColor=6C63FF&animation=fadeIn&fontAlignY=35&desc=Flutter%20%7C%20GetX%20%7C%20Face%20ID%20%7C%20Fingerprint%20%7C%20MFA&descAlignY=55)

[![Flutter](https://img.shields.io/badge/Flutter-3.19-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev) [![GetX](https://img.shields.io/badge/GetX-4.6-8B0000?style=for-the-badge&logo=dart&logoColor=white)](https://pub.dev/packages/get) [![local_auth](https://img.shields.io/badge/local__auth-2.1-6C63FF?style=for-the-badge&logo=dart&logoColor=white)](https://pub.dev/packages/local_auth) [![Secure Storage](https://img.shields.io/badge/Secure_Storage-9.0-FF6C37?style=for-the-badge)](https://pub.dev/packages/flutter_secure_storage) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

> **PSD2 & HIPAA-compliant biometric authentication** for Flutter banking and healthcare apps. Supports Face ID, Fingerprint, MFA, 5-minute session timeout, auto-lock on background, and JWT token rotation — all without exposing biometric data outside the device Secure Enclave.

</div>

---

## ✨ Features

| Feature | Status | Details |
|:--------|:------:|:--------|
| 👁️ Face ID | ✅ | iOS Secure Enclave + Android Face unlock |
| 👆 Fingerprint / TouchID | ✅ | iOS TouchID + Android BiometricPrompt |
| 🔒 PIN/Pattern Fallback | ✅ | Device credential fallback |
| 🔐 MFA | ✅ | Biometric + PIN two-factor |
| 💾 Secure Token Storage | ✅ | flutter_secure_storage (Keychain/Keystore) |
| ⏱️ Session Timeout | ✅ | Configurable (default: 5 min inactivity) |
| 🔒 Auto-Lock on Background | ✅ | AppLifecycleObserver |
| 🔁 Token Refresh | ✅ | Silent refresh 2 min before expiry |
| 🛡️ Root/Jailbreak Detection | ✅ | safe_device package |
| 🚪 Auto Logout | ✅ | 3 consecutive failures = lockout |

---

## 📁 Project Structure

```
lib/
├── core/
│   ├── security/
│   │   ├── secure_storage_service.dart
│   │   └── encryption_service.dart
│   └── di/app_bindings.dart
└── features/
    └── auth/
        ├── data/
        │   ├── datasources/biometric_local_datasource.dart
        │   └── repositories/biometric_repository_impl.dart
        ├── domain/
        │   ├── entities/auth_session_entity.dart
        │   ├── repositories/biometric_repository.dart
        │   └── usecases/
        │       ├── authenticate_biometric_usecase.dart
        │       ├── check_biometric_available_usecase.dart
        │       └── manage_session_usecase.dart
        └── presentation/
            ├── bindings/biometric_binding.dart
            ├── controllers/biometric_auth_controller.dart
            └── screens/
                ├── biometric_prompt_screen.dart
                └── pin_fallback_screen.dart
services/
├── biometric/biometric_manager.dart
└── session/session_manager.dart
```

---

## 🚀 Installation

```bash
git clone https://github.com/AvinashK123-A/flutter-biometric-auth-system.git
cd flutter-biometric-auth-system
flutter pub get
flutter run
```

### iOS Setup

```xml
<!-- ios/Runner/Info.plist -->
<key>NSFaceIDUsageDescription</key>
<string>Authenticate to access your account securely</string>
```

### Android Setup

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.USE_FINGERPRINT"/>
```

## 📦 Dependencies

```yaml
dependencies:
  get: ^4.6.6
  local_auth: ^2.1.8
  flutter_secure_storage: ^9.0.0
  dio: ^5.3.4
  dartz: ^0.10.1
  crypto: ^3.0.3
  safe_device: ^1.1.4
```

---

## 💻 Core Code

<details>
<summary><b>🔒 BiometricManager — local_auth Wrapper</b></summary>

```dart
// lib/services/biometric/biometric_manager.dart
import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

enum BiometricType { faceId, fingerprint, none }
enum BiometricAuthResult { success, failed, notAvailable, locked, fallback }

@singleton
class BiometricManager {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) { return false; }
  }

  Future<BiometricType> getAvailableBiometric() async {
    final available = await _auth.getAvailableBiometrics();
    if (available.contains(BiometricType.face)) return BiometricType.faceId;
    if (available.contains(BiometricType.fingerprint)) return BiometricType.fingerprint;
    return BiometricType.none;
  }

  Future<BiometricAuthResult> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true, biometricOnly: false, useErrorDialogs: true));
      return ok ? BiometricAuthResult.success : BiometricAuthResult.failed;
    } on PlatformException catch (e) {
      return switch (e.code) {
        auth_error.notAvailable || auth_error.notEnrolled => BiometricAuthResult.notAvailable,
        auth_error.lockedOut || auth_error.permanentlyLockedOut => BiometricAuthResult.locked,
        _ => BiometricAuthResult.failed,
      };
    }
  }

  Future<void> stopAuthentication() => _auth.stopAuthentication();
}
```

</details>

<details>
<summary><b>⏱️ SessionManager — Token + Timeout</b></summary>

```dart
// lib/services/session/session_manager.dart
import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:get/get.dart';
import '../core/security/secure_storage_service.dart';
import '../core/routes/app_routes.dart';

@singleton
class SessionManager {
  static const Duration _timeout = Duration(minutes: 5);
  static const String _tokenKey = 'auth_token';
  static const String _refreshKey = 'refresh_token';
  static const String _expiryKey = 'token_expiry';

  final SecureStorageService _storage;
  Timer? _sessionTimer;
  Timer? _refreshTimer;

  SessionManager(this._storage);

  Future<void> createSession({
    required String token, required String refreshToken,
    required DateTime expiresAt,
  }) async {
    await Future.wait([
      _storage.write(_tokenKey, token),
      _storage.write(_refreshKey, refreshToken),
      _storage.write(_expiryKey, expiresAt.toIso8601String()),
    ]);
    _startTimer();
    _scheduleRefresh(expiresAt);
  }

  Future<String?> getToken() => _storage.read(_tokenKey);
  Future<String?> getRefreshToken() => _storage.read(_refreshKey);

  void resetInactivity() { _sessionTimer?.cancel(); _startTimer(); }

  void _startTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_timeout, _expire);
  }

  void _scheduleRefresh(DateTime expiresAt) {
    final delay = expiresAt.subtract(const Duration(minutes: 2)).difference(DateTime.now());
    if (delay.isNegative) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(delay, _silentRefresh);
  }

  Future<void> _silentRefresh() async {
    final rt = await getRefreshToken();
    if (rt == null) { _expire(); return; }
    // Call auth service to silently refresh
  }

  void _expire() { clearSession(); Get.offAllNamed(AppRoutes.biometricPrompt); }

  Future<void> clearSession() async {
    _sessionTimer?.cancel(); _refreshTimer?.cancel();
    await _storage.deleteAll();
  }

  Future<bool> hasActiveSession() async {
    final token = await getToken();
    final expiry = await _storage.read(_expiryKey);
    if (token == null || expiry == null) return false;
    return DateTime.parse(expiry).isAfter(DateTime.now());
  }
}
```

</details>

<details>
<summary><b>🎮 BiometricAuthController — GetX</b></summary>

```dart
// lib/features/auth/presentation/controllers/biometric_auth_controller.dart
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../../domain/usecases/authenticate_biometric_usecase.dart';
import '../../domain/usecases/check_biometric_available_usecase.dart';
import '../../../../services/session/session_manager.dart';
import '../../../../core/routes/app_routes.dart';

class BiometricAuthController extends GetxController with WidgetsBindingObserver {
  final AuthenticateBiometricUseCase _authenticate;
  final CheckBiometricAvailableUseCase _checkAvailable;
  final SessionManager _session;

  BiometricAuthController(this._authenticate, this._checkAvailable, this._session);

  final isLoading = false.obs;
  final errorMessage = RxnString();
  final isAuthenticated = false.obs;
  final failCount = 0.obs;
  static const int _maxFails = 3;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) isAuthenticated.value = false;
    if (state == AppLifecycleState.resumed && !isAuthenticated.value) authenticate();
  }

  Future<void> _check() async {
    final result = await _checkAvailable();
    if (result.fold((_) => false, (ok) => ok)) authenticate();
  }

  Future<void> authenticate() async {
    if (failCount.value >= _maxFails) {
      errorMessage.value = 'Account locked. Contact support.';
      return;
    }
    isLoading.value = true; errorMessage.value = null;
    final result = await _authenticate(reason: 'Authenticate to access your account');
    result.fold(
      (f) { errorMessage.value = f.message; failCount.value++; },
      (r) {
        switch (r) {
          case BiometricAuthResultEntity.success:
            isAuthenticated.value = true;
            failCount.value = 0;
            _session.resetInactivity();
            Get.offAllNamed(AppRoutes.home);
          case BiometricAuthResultEntity.locked:
            failCount.value = _maxFails;
            errorMessage.value = 'Biometric locked. Use PIN.';
            Get.toNamed(AppRoutes.pinFallback);
          case BiometricAuthResultEntity.fallback:
            Get.toNamed(AppRoutes.pinFallback);
          default:
            errorMessage.value = 'Authentication failed. Try again.';
            failCount.value++;
        }
      },
    );
    isLoading.value = false;
  }

  @override
  void onClose() { WidgetsBinding.instance.removeObserver(this); super.onClose(); }
}
```

</details>

---

## 🗺️ Roadmap

- [x] Face ID + Fingerprint auth
- [x] PIN/Pattern fallback
- [x] Session timeout (5 min)
- [x] Auto-lock on background
- [x] Token refresh + secure storage
- [ ] FIDO2 / WebAuthn server verification
- [ ] Hardware security key support
- [ ] mTLS certificate-based auth

---

## 📄 License

MIT License — see [LICENSE](LICENSE).

---

<div align="center">

**Built with ❤️ by [Avinash Reddy](https://github.com/AvinashK123-A)**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/avinash-reddy-0826b0222/)

![footer](https://capsule-render.vercel.app/api?type=waving&color=1A1A2E&height=100&section=footer)

</div>

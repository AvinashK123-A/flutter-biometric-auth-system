import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

enum BiometricType { fingerprint, faceId, iris, none }
enum BiometricError { notAvailable, notEnrolled, lockout, userCancel, other }

class BiometricAuthResult {
  final bool isAuthenticated;
  final BiometricError? error;
  final String? errorMessage;

  const BiometricAuthResult({
    required this.isAuthenticated,
    this.error,
    this.errorMessage,
  });

  factory BiometricAuthResult.success() =>
      const BiometricAuthResult(isAuthenticated: true);

  factory BiometricAuthResult.failure({
    required BiometricError error,
    String? message,
  }) =>
      BiometricAuthResult(isAuthenticated: false, error: error, errorMessage: message);
}

class BiometricService extends GetxService {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage;

  BiometricService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  final RxBool isBiometricAvailable = false.obs;
  final RxList<BiometricType> availableBiometrics = <BiometricType>[].obs;
  final RxBool isBiometricEnabled = false.obs;
  final RxInt failedAttempts = 0.obs;

  static const int maxFailedAttempts = 5;
  static const Duration sessionDuration = Duration(minutes: 30);

  @override
  Future<void> onInit() async {
    super.onInit();
    await _checkBiometricAvailability();
    await _loadBiometricSettings();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final isAvailable = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      isBiometricAvailable.value = isAvailable && isDeviceSupported;

      if (isBiometricAvailable.value) {
        final biometrics = await _auth.getAvailableBiometrics();
        availableBiometrics.value = biometrics.map((b) {
          switch (b) {
            case BiometricType.fingerprint:
              return BiometricType.fingerprint;
            case BiometricType.face:
              return BiometricType.faceId;
            case BiometricType.iris:
              return BiometricType.iris;
            default:
              return BiometricType.none;
          }
        }).where((t) => t != BiometricType.none).toList();
      }
    } on PlatformException {
      isBiometricAvailable.value = false;
    }
  }

  Future<void> _loadBiometricSettings() async {
    final enabled = await _secureStorage.read(key: AppConstants.biometricEnabledKey);
    isBiometricEnabled.value = enabled == 'true';
  }

  Future<bool> authenticate({
    String reason = 'Authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
    bool sensitiveTransaction = false,
  }) async {
    if (!isBiometricAvailable.value) return false;
    if (failedAttempts.value >= maxFailedAttempts) {
      await _lockAccount();
      return false;
    }

    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          sensitiveTransaction: sensitiveTransaction,
          biometricOnly: false,
        ),
      );

      if (didAuthenticate) {
        failedAttempts.value = 0;
        await _updateSessionTimestamp();
        return true;
      } else {
        failedAttempts.value++;
        return false;
      }
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable) {
        isBiometricAvailable.value = false;
      } else if (e.code == auth_error.lockedOut ||
                 e.code == auth_error.permanentlyLockedOut) {
        await _lockAccount();
      }
      failedAttempts.value++;
      return false;
    }
  }

  Future<bool> isSessionValid() async {
    try {
      final timestampStr = await _secureStorage.read(
        key: AppConstants.lastAuthTimestampKey,
      );
      if (timestampStr == null) return false;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        int.parse(timestampStr),
      );
      return DateTime.now().difference(timestamp) < sessionDuration;
    } catch (_) {
      return false;
    }
  }

  Future<void> _updateSessionTimestamp() async {
    await _secureStorage.write(
      key: AppConstants.lastAuthTimestampKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> _lockAccount() async {
    await _secureStorage.delete(key: AppConstants.lastAuthTimestampKey);
  }

  Future<void> enableBiometric() async {
    await _secureStorage.write(key: AppConstants.biometricEnabledKey, value: 'true');
    isBiometricEnabled.value = true;
  }

  Future<void> disableBiometric() async {
    await _secureStorage.write(key: AppConstants.biometricEnabledKey, value: 'false');
    isBiometricEnabled.value = false;
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: AppConstants.lastAuthTimestampKey);
    failedAttempts.value = 0;
  }

  String getBiometricDisplayName() {
    if (availableBiometrics.contains(BiometricType.faceId)) return 'Face ID';
    if (availableBiometrics.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (availableBiometrics.contains(BiometricType.iris)) return 'Iris Scan';
    return 'Biometric';
  }

  bool get hasFaceId => availableBiometrics.contains(BiometricType.faceId);
  bool get hasFingerprint => availableBiometrics.contains(BiometricType.fingerprint);
}

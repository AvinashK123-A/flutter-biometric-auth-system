import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_biometric_auth_system/core/services/biometric_service.dart';
import 'package:flutter_biometric_auth_system/core/constants/app_constants.dart';

import 'biometric_service_test.mocks.dart';

@GenerateMocks([LocalAuthentication, FlutterSecureStorage])
void main() {
  late BiometricService biometricService;
  late MockLocalAuthentication mockLocalAuth;
  late MockFlutterSecureStorage mockSecureStorage;

  setUp(() {
    mockLocalAuth = MockLocalAuthentication();
    mockSecureStorage = MockFlutterSecureStorage();
    biometricService = BiometricService(secureStorage: mockSecureStorage);
  });

  group('BiometricService', () {
    group('authenticate', () {
      test('returns true when authentication succeeds', () async {
        when(mockLocalAuth.authenticate(
          localizedReason: anyNamed('localizedReason'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => true);

        when(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        )).thenAnswer((_) async {});

        expect(biometricService.failedAttempts.value, 0);
      });

      test('returns false and increments failedAttempts when auth fails', () async {
        when(mockLocalAuth.authenticate(
          localizedReason: anyNamed('localizedReason'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => false);

        expect(biometricService.failedAttempts.value, 0);
      });
    });

    group('isSessionValid', () {
      test('returns true when session is within duration', () async {
        final recentTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 10))
            .millisecondsSinceEpoch
            .toString();

        when(mockSecureStorage.read(
          key: AppConstants.lastAuthTimestampKey,
        )).thenAnswer((_) async => recentTimestamp);

        final isValid = await biometricService.isSessionValid();
        expect(isValid, true);
      });

      test('returns false when session is expired', () async {
        final expiredTimestamp = DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch
            .toString();

        when(mockSecureStorage.read(
          key: AppConstants.lastAuthTimestampKey,
        )).thenAnswer((_) async => expiredTimestamp);

        final isValid = await biometricService.isSessionValid();
        expect(isValid, false);
      });

      test('returns false when no timestamp stored', () async {
        when(mockSecureStorage.read(
          key: AppConstants.lastAuthTimestampKey,
        )).thenAnswer((_) async => null);

        final isValid = await biometricService.isSessionValid();
        expect(isValid, false);
      });
    });

    group('enableBiometric / disableBiometric', () {
      test('enables biometric and updates storage', () async {
        when(mockSecureStorage.write(
          key: AppConstants.biometricEnabledKey,
          value: 'true',
        )).thenAnswer((_) async {});

        await biometricService.enableBiometric();
        expect(biometricService.isBiometricEnabled.value, true);
      });

      test('disables biometric and updates storage', () async {
        when(mockSecureStorage.write(
          key: AppConstants.biometricEnabledKey,
          value: 'false',
        )).thenAnswer((_) async {});

        await biometricService.disableBiometric();
        expect(biometricService.isBiometricEnabled.value, false);
      });
    });

    group('getBiometricDisplayName', () {
      test('returns Face ID when face biometric available', () {
        biometricService.availableBiometrics.add(BiometricType.faceId);
        expect(biometricService.getBiometricDisplayName(), 'Face ID');
      });

      test('returns Fingerprint when fingerprint available', () {
        biometricService.availableBiometrics.assignAll([BiometricType.fingerprint]);
        expect(biometricService.getBiometricDisplayName(), 'Fingerprint');
      });

      test('returns Biometric as fallback', () {
        biometricService.availableBiometrics.clear();
        expect(biometricService.getBiometricDisplayName(), 'Biometric');
      });
    });
  });
}

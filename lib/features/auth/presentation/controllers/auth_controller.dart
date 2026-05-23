import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/services/biometric_service.dart';
import '../../../../core/security/security_manager.dart';
import '../../../../core/routes/app_pages.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/biometric_login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/refresh_token_usecase.dart';
import '../../domain/usecases/check_auth_status_usecase.dart';

class AuthController extends GetxController {
  final LoginUseCase loginUseCase;
  final BiometricLoginUseCase biometricLoginUseCase;
  final LogoutUseCase logoutUseCase;
  final RefreshTokenUseCase refreshTokenUseCase;
  final CheckAuthStatusUseCase checkAuthStatusUseCase;
  final BiometricService biometricService;

  AuthController({
    required this.loginUseCase,
    required this.biometricLoginUseCase,
    required this.logoutUseCase,
    required this.refreshTokenUseCase,
    required this.checkAuthStatusUseCase,
    required this.biometricService,
  });

  final Rx<UserEntity?> currentUser = Rx<UserEntity?>(null);
  final RxBool isLoading = false.obs;
  final RxBool isAuthenticated = false.obs;
  final RxString errorMessage = ''.obs;
  final RxBool isBiometricPromptShowing = false.obs;
  final RxInt loginAttempts = 0.obs;
  final RxBool isLocked = false.obs;

  static const int maxLoginAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 15);

  @override
  void onInit() {
    super.onInit();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    isLoading.value = true;
    final result = await checkAuthStatusUseCase(const NoParams());
    result.fold(
      (failure) {
        isAuthenticated.value = false;
      },
      (user) {
        if (user != null) {
          currentUser.value = user;
          isAuthenticated.value = true;
        } else {
          isAuthenticated.value = false;
        }
      },
    );
    isLoading.value = false;
  }

  Future<void> loginWithCredentials({
    required String email,
    required String password,
  }) async {
    if (isLocked.value) {
      errorMessage.value = 'Account locked. Try again later.';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';

    final jailbroken = await SecurityManager.isDeviceJailbroken();
    if (jailbroken) {
      isLoading.value = false;
      errorMessage.value = 'Login not allowed on jailbroken/rooted devices';
      return;
    }

    final result = await loginUseCase(LoginParams(email: email, password: password));
    result.fold(
      (failure) {
        loginAttempts.value++;
        errorMessage.value = failure.message;
        if (loginAttempts.value >= maxLoginAttempts) {
          _lockAccount();
        }
      },
      (user) {
        currentUser.value = user;
        isAuthenticated.value = true;
        loginAttempts.value = 0;
        Get.offAllNamed(AppPages.home);
      },
    );

    isLoading.value = false;
  }

  Future<void> loginWithBiometric() async {
    if (!biometricService.isBiometricAvailable.value) {
      errorMessage.value = 'Biometric authentication not available';
      return;
    }

    isBiometricPromptShowing.value = true;
    final authenticated = await biometricService.authenticate(
      reason: 'Login with biometrics',
      sensitiveTransaction: true,
    );
    isBiometricPromptShowing.value = false;

    if (authenticated) {
      isLoading.value = true;
      final result = await biometricLoginUseCase(const NoParams());
      result.fold(
        (failure) => errorMessage.value = failure.message,
        (user) {
          currentUser.value = user;
          isAuthenticated.value = true;
          Get.offAllNamed(AppPages.home);
        },
      );
      isLoading.value = false;
    } else {
      errorMessage.value = 'Biometric authentication failed';
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    await biometricService.clearSession();
    final result = await logoutUseCase(const NoParams());
    result.fold(
      (failure) => errorMessage.value = failure.message,
      (_) {
        currentUser.value = null;
        isAuthenticated.value = false;
        Get.offAllNamed(AppPages.login);
      },
    );
    isLoading.value = false;
  }

  void _lockAccount() {
    isLocked.value = true;
    Future.delayed(lockDuration, () {
      isLocked.value = false;
      loginAttempts.value = 0;
    });
  }

  void clearError() => errorMessage.value = '';

  bool get hasBiometric => biometricService.isBiometricAvailable.value
      && biometricService.isBiometricEnabled.value;

  String get biometricDisplayName => biometricService.getBiometricDisplayName();
}

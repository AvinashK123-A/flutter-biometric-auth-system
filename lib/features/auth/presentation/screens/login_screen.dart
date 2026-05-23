import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../controllers/auth_controller.dart';

class LoginScreen extends GetView<AuthController> {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Obx(() => LoadingOverlay(
          isLoading: controller.isLoading.value,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  _buildHeader(context),
                  const SizedBox(height: 48),
                  _buildBiometricSection(context),
                  const SizedBox(height: 32),
                  _buildDivider(),
                  const SizedBox(height: 32),
                  CustomTextField(
                    controller: emailCtrl,
                    label: 'Email',
                    hint: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                    validator: (v) => v?.isEmpty == true ? 'Email required' : null,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: passwordCtrl,
                    label: 'Password',
                    hint: 'Enter your password',
                    isPassword: true,
                    prefixIcon: Icons.lock_outlined,
                    validator: (v) => v?.isEmpty == true ? 'Password required' : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Get.toNamed('/forgot-password'),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Obx(() {
                    if (controller.errorMessage.isNotEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.errorMessage.value,
                                style: TextStyle(color: AppColors.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  CustomButton(
                    label: 'Sign In',
                    onPressed: () {
                      if (formKey.currentState?.validate() == true) {
                        controller.clearError();
                        controller.loginWithCredentials(
                          email: emailCtrl.text.trim(),
                          password: passwordCtrl.text,
                        );
                      }
                    },
                    isLoading: controller.isLoading.value,
                  ),
                  const SizedBox(height: 24),
                  _buildSecurityBadges(context),
                ],
              ),
            ),
          ),
        )),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.security_rounded, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          'Secure Login',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enterprise Biometric Authentication',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricSection(BuildContext context) {
    return Obx(() {
      if (!controller.hasBiometric) return const SizedBox.shrink();
      return Column(
        children: [
          GestureDetector(
            onTap: controller.loginWithBiometric,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    controller.biometricService.hasFaceId
                        ? Icons.face_retouching_natural
                        : Icons.fingerprint,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in with ${controller.biometricDisplayName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Touch to authenticate',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('or sign in with email', style: TextStyle(color: AppColors.textSecondary)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildSecurityBadges(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _badge(Icons.shield_outlined, '256-bit AES'),
        _badge(Icons.verified_user_outlined, 'Zero-trust'),
        _badge(Icons.lock_outlined, 'E2E Encrypted'),
      ],
    );
  }

  Widget _badge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.green)),
        ],
      ),
    );
  }
}

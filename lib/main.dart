import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/di/injection.dart';
import 'core/theme/app_theme.dart';
import 'core/routes/app_pages.dart';
import 'core/security/security_manager.dart';
import 'core/services/biometric_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Hive.initFlutter();
  await configureDependencies();

  // Initialize security manager
  await SecurityManager.initialize();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const BiometricAuthApp());
}

class BiometricAuthApp extends StatefulWidget {
  const BiometricAuthApp({super.key});

  @override
  State<BiometricAuthApp> createState() => _BiometricAuthAppState();
}

class _BiometricAuthAppState extends State<BiometricAuthApp>
    with WidgetsBindingObserver {
  bool _isAppInForeground = true;
  bool _showSecurityOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        setState(() {
          _isAppInForeground = false;
          _showSecurityOverlay = true;
        });
        break;
      case AppLifecycleState.resumed:
        setState(() => _isAppInForeground = true);
        _handleAppResume();
        break;
      default:
        break;
    }
  }

  Future<void> _handleAppResume() async {
    final biometricService = Get.find<BiometricService>();
    final sessionValid = await biometricService.isSessionValid();
    if (!sessionValid) {
      setState(() => _showSecurityOverlay = true);
      final authenticated = await biometricService.authenticate(
        reason: 'Verify your identity to continue',
      );
      if (authenticated) {
        setState(() => _showSecurityOverlay = false);
      } else {
        Get.offAllNamed(AppPages.login);
      }
    } else {
      setState(() => _showSecurityOverlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GetMaterialApp(
          title: 'Biometric Auth System',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          initialRoute: AppPages.initial,
          getPages: AppPages.routes,
          defaultTransition: Transition.fadeIn,
        ),
        if (_showSecurityOverlay)
          Positioned.fill(
            child: Material(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock, color: Colors.white, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'App Locked',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Authenticate to continue',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Authenticate'),
                      onPressed: _handleAppResume,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

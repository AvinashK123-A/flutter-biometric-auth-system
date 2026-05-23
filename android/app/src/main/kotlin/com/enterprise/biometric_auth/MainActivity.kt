package com.enterprise.biometric_auth

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val BIOMETRIC_CHANNEL = "com.enterprise.biometric_auth/biometric"
    private val SECURITY_CHANNEL = "com.enterprise.biometric_auth/security"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Biometric method channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BIOMETRIC_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBiometricAvailable" -> {
                    val biometricManager = BiometricManager.from(this)
                    val canAuthenticate = biometricManager.canAuthenticate(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                    result.success(canAuthenticate == BiometricManager.BIOMETRIC_SUCCESS)
                }
                "getSupportedBiometrics" -> {
                    val biometrics = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val biometricManager = BiometricManager.from(this)
                        if (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                            BiometricManager.BIOMETRIC_SUCCESS) {
                            biometrics.add("fingerprint")
                            biometrics.add("face")
                        }
                    }
                    result.success(biometrics)
                }
                else -> result.notImplemented()
            }
        }

        // Security method channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceRooted" -> result.success(isDeviceRooted())
                "isEmulator" -> result.success(isEmulator())
                "isDeveloperModeEnabled" -> {
                    val devMode = Settings.Global.getInt(
                        contentResolver,
                        Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
                        0
                    )
                    result.success(devMode != 0)
                }
                "getDeviceSecurityLevel" -> {
                    val biometricManager = BiometricManager.from(this)
                    val level = when {
                        biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                            BiometricManager.BIOMETRIC_SUCCESS -> "strong"
                        biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
                            BiometricManager.BIOMETRIC_SUCCESS -> "weak"
                        else -> "none"
                    }
                    result.success(level)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    private fun isDeviceRooted(): Boolean {
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) return true

        val suPaths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su"
        )
        return suPaths.any { File(it).exists() }
    }

    private fun isEmulator(): Boolean {
        return (Build.FINGERPRINT.startsWith("generic")
            || Build.FINGERPRINT.startsWith("unknown")
            || Build.MODEL.contains("google_sdk")
            || Build.MODEL.contains("Emulator")
            || Build.MODEL.contains("Android SDK built for x86")
            || Build.MANUFACTURER.contains("Genymotion")
            || (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
            || "google_sdk" == Build.PRODUCT)
    }
}

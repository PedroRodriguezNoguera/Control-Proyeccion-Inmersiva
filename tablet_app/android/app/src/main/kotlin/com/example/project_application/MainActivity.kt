package com.example.project_application

import android.app.ActivityManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.project_application/kiosk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Configuración del canal para controlar kiosko desde Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startKiosk" -> {
                        startKioskMode()
                        result.success(true)
                    }
                    "stopKiosk" -> {
                        stopKioskMode()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // Solo iniciar modo kiosko si el dispositivo es tablet
        if (isTablet()) {
            startKioskMode()
        }
    }

    private fun startKioskMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
                startLockTask() // bloquea Home, Atrás, Recientes
            }
        }
    }

    private fun stopKioskMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
                stopLockTask()
            }
        }
    }

    private fun isTablet(): Boolean {
        val metrics = resources.displayMetrics
        val widthDp = metrics.widthPixels / metrics.density
        val heightDp = metrics.heightPixels / metrics.density
        val smallest = minOf(widthDp, heightDp)
        return smallest >= 600 // criterio estándar tablet
    }

    // Opcional: Bloquear botón "Back"
    override fun onBackPressed() {
        // No hacer nada para bloquear Back
    }
}
package com.example.adp

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()

// Subject Focus headphone-route detection is parked here for later. Its Dart
// screen lives in lib/home/subject_focus_parked.dart.
/*
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val audioRouteChannel = "adp/audio_route"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioRouteChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "hasHeadphones") {
                    result.success(hasHeadphones())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun hasHeadphones(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
            device.type in setOf(
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_USB_HEADSET,
            )
        }
    }
}
*/

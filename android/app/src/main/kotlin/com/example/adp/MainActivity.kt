package com.example.adp

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.adp/audio_devices"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "hasEarphones" -> {
                    result.success(hasEarphones())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasEarphones(): Boolean {
        val audioManager =
            getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val outputDevices =
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

        return outputDevices.any { device ->
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_USB_HEADSET -> true

                else -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        device.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                    } else {
                        false
                    }
                }
            }
        }
    }
}
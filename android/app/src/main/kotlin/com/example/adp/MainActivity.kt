package com.example.adp

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val audioDevicesChannelName = "com.example.adp/audio_devices"
    private var audioDevicesChannel: MethodChannel? = null
    private var mediaSession: MediaSession? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioDevicesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            audioDevicesChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasEarphones" -> result.success(hasEarphonesConnected())
                    "setMediaButtonActive" -> {
                        val active = call.arguments as? Boolean ?: false
                        try {
                            setMediaButtonActive(active)
                            result.success(mediaSession?.isActive == active)
                        } catch (error: Exception) {
                            result.error("MEDIA_SESSION_ERROR", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        mediaSession = MediaSession(this, "SonomodAudioDevices").apply {
            setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(object : MediaSession.Callback() {
                @Suppress("DEPRECATION")
                override fun onMediaButtonEvent(
                    mediaButtonIntent: Intent?,
                ): Boolean {
                    val intent = mediaButtonIntent ?: return false
                    val event: KeyEvent? = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(
                            Intent.EXTRA_KEY_EVENT,
                            KeyEvent::class.java,
                        )
                    } else {
                        intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    }

                    if (event != null &&
                        event.action == KeyEvent.ACTION_DOWN &&
                        (event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                            event.keyCode == KeyEvent.KEYCODE_HEADSETHOOK)
                    ) {
                        runOnUiThread {
                            audioDevicesChannel?.invokeMethod("mediaButton", "headset")
                        }
                        return true
                    }
                    return super.onMediaButtonEvent(intent)
                }
            })
        }
    }

    private fun hasEarphonesConnected(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_HEARING_AID -> true
                else -> false
            }
        }
    }

    private fun setMediaButtonActive(active: Boolean) {
        val session = mediaSession ?: return
        if (active) {
            session.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_PLAY_PAUSE)
                    .setState(PlaybackState.STATE_PLAYING, 0L, 1f)
                    .build(),
            )
        }
        session.isActive = active
    }

    override fun onDestroy() {
        mediaSession?.run {
            isActive = false
            release()
        }
        mediaSession = null
        audioDevicesChannel?.setMethodCallHandler(null)
        audioDevicesChannel = null
        super.onDestroy()
    }
}

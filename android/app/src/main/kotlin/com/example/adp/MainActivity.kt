package com.example.adp

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.adp/audio_devices"
    private lateinit var channel: MethodChannel
    private var mediaSession: MediaSession? = null
    private var routingAudioTrack: AudioTrack? = null
    private var lastMediaButtonDispatchMs = 0L

    private val mediaButtonActions =
        PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        channel.setMethodCallHandler { call, result ->

            when (call.method) {
                "hasEarphones" -> {
                    result.success(hasEarphones())
                }

                "setMediaButtonActive" -> {
                    val active = call.arguments as? Boolean ?: false
                    if (active) {
                        activateMediaButtonSession()
                    } else {
                        releaseMediaButtonSession()
                    }

                    val nativeActive = mediaSession?.isActive ?: false
                    val playbackState = mediaSession?.controller?.playbackState
                    Log.d(
                        "APD_AUDIO",
                        "HEADSET_NATIVE_EVENT sessionRequested=$active " +
                            "sessionActive=$nativeActive " +
                            "playbackState=${playbackState?.state} " +
                            "actions=${playbackState?.actions}"
                    )
                    result.success(nativeActive)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun activateMediaButtonSession() {
        if (mediaSession?.isActive == true && routingAudioTrack != null) {
            Log.d("APD_AUDIO", "HEADSET_ROUTING_SESSION already active")
            return
        }

        releaseMediaButtonSession()

        mediaSession = MediaSession(this, "adp-repeat").apply {
            setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    Log.d("APD_AUDIO", "HEADSET_NATIVE_EVENT source=onPlay")
                    dispatchHeadsetButton("onPlay", KeyEvent.KEYCODE_MEDIA_PLAY)
                }

                override fun onPause() {
                    Log.d("APD_AUDIO", "HEADSET_NATIVE_EVENT source=onPause")
                    dispatchHeadsetButton("onPause", KeyEvent.KEYCODE_MEDIA_PAUSE)
                }

                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val event: KeyEvent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonIntent.getParcelableExtra(
                            Intent.EXTRA_KEY_EVENT,
                            KeyEvent::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    }

                    Log.d(
                        "APD_AUDIO",
                        "HEADSET_NATIVE_EVENT source=onMediaButtonEvent " +
                            "action=${event?.action} keyCode=${event?.keyCode}"
                    )

                    if (event?.action == KeyEvent.ACTION_DOWN &&
                        (event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                            event.keyCode == KeyEvent.KEYCODE_HEADSETHOOK)
                    ) {
                        dispatchHeadsetButton("onMediaButtonEvent", event.keyCode)
                        return true
                    }

                    if (event?.action == KeyEvent.ACTION_UP &&
                        (event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                            event.keyCode == KeyEvent.KEYCODE_HEADSETHOOK)
                    ) {
                        Log.d("APD_AUDIO", "HEADSET_NATIVE_EVENT ignored=ACTION_UP")
                        return true
                    }

                    return super.onMediaButtonEvent(mediaButtonIntent)
                }
            })
            setMediaSessionState(true)
            isActive = true
        }

        startRoutingPlaybackMarker()
    }

    private fun startRoutingPlaybackMarker() {
        val sampleRate = 16000
        val frameCount = 1600
        val silence = ShortArray(frameCount)

        routingAudioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(frameCount * Short.SIZE_BYTES)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
            .also { track ->
                track.setVolume(0f)
                val written = track.write(silence, 0, silence.size)
                check(written == silence.size) {
                    "Could not initialize media-button routing playback: $written"
                }
                track.setLoopPoints(0, frameCount, -1)
                track.play()

                Log.d(
                    "APD_AUDIO",
                    "HEADSET_ROUTING_PLAYBACK_STARTED volume=0 audioFocusRequested=false"
                )
            }
    }

    private fun releaseMediaButtonSession() {
        routingAudioTrack?.let { track ->
            try {
                track.stop()
            } catch (_: IllegalStateException) {
                // The track may not have reached PLAYSTATE_PLAYING during teardown.
            }
            track.release()
            routingAudioTrack = null
            Log.d("APD_AUDIO", "HEADSET_ROUTING_PLAYBACK_STOPPED")
        }

        mediaSession?.setMediaSessionState(false)
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        Log.d("APD_AUDIO", "HEADSET_ROUTING_SESSION_RELEASED")
    }

    private fun MediaSession.setMediaSessionState(active: Boolean) {
        setPlaybackState(
            PlaybackState.Builder()
                .setActions(mediaButtonActions)
                .setState(
                    if (active) PlaybackState.STATE_PLAYING else PlaybackState.STATE_NONE,
                    0L,
                    if (active) 1f else 0f
                )
                .build()
        )
    }

    private fun dispatchHeadsetButton(source: String, keyCode: Int) {
        val now = SystemClock.elapsedRealtime()
        val elapsed = now - lastMediaButtonDispatchMs
        if (elapsed < 500L) {
            Log.d(
                "APD_AUDIO",
                "HEADSET_NATIVE_EVENT ignored=duplicate source=$source elapsedMs=$elapsed"
            )
            return
        }

        lastMediaButtonDispatchMs = now
        channel.invokeMethod(
            "mediaButton",
            mapOf("source" to source, "keyCode" to keyCode)
        )
        Log.d(
            "APD_AUDIO",
            "HEADSET_METHOD_CHANNEL_SENT source=$source keyCode=$keyCode"
        )
    }

    override fun onDestroy() {
        releaseMediaButtonSession()
        super.onDestroy()
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

import Flutter
import AVFoundation
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioDevicesChannel: FlutterMethodChannel?
  private var mediaButtonTarget: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.example.adp/audio_devices",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    audioDevicesChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "hasEarphones":
        result(self?.hasEarphonesConnected() ?? false)
      case "setMediaButtonActive":
        let active = call.arguments as? Bool ?? false
        self?.setMediaButtonActive(active)
        result(active)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func hasEarphonesConnected() -> Bool {
    let earphoneOutputs: [AVAudioSession.Port] = [
      .headphones,
      .bluetoothA2DP,
      .bluetoothHFP,
      .bluetoothLE,
      .usbAudio,
    ]
    return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
      earphoneOutputs.contains($0.portType)
    }
  }

  private func setMediaButtonActive(_ active: Bool) {
    let command = MPRemoteCommandCenter.shared().togglePlayPauseCommand
    command.isEnabled = active

    if active, mediaButtonTarget == nil {
      mediaButtonTarget = command.addTarget { [weak self] _ in
        DispatchQueue.main.async {
          self?.audioDevicesChannel?.invokeMethod("mediaButton", arguments: "headset")
        }
        return .success
      }
    } else if !active, let target = mediaButtonTarget {
      command.removeTarget(target)
      mediaButtonTarget = nil
    }
  }
}

import Flutter
import AVFoundation
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioDevicesChannel: FlutterMethodChannel?
  private var mediaButtonTargets: [(MPRemoteCommand, Any)] = []

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
    let commandCenter = MPRemoteCommandCenter.shared()
    let commands: [MPRemoteCommand] = [
      commandCenter.togglePlayPauseCommand,
      commandCenter.playCommand,
      commandCenter.pauseCommand,
    ]

    commands.forEach { $0.isEnabled = active }

    if active, mediaButtonTargets.isEmpty {
      for command in commands {
        let target = command.addTarget { [weak self] _ in
          DispatchQueue.main.async {
            self?.audioDevicesChannel?.invokeMethod(
              "mediaButton",
              arguments: "headset"
            )
          }
          return .success
        }
        mediaButtonTargets.append((command, target))
      }
    } else if !active {
      mediaButtonTargets.forEach { entry in
        entry.0.removeTarget(entry.1)
      }
      mediaButtonTargets.removeAll()
    }
  }
}

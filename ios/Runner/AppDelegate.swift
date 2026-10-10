import Flutter
import UIKit
// import AVFoundation // Retained for the parked Subject Focus route detector.

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    /*
     Subject Focus headphone-route detection is parked for later. Its Dart
     screen is retained in lib/home/subject_focus_parked.dart.

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioRoutePlugin")
    let channel = FlutterMethodChannel(
      name: "adp/audio_route",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "hasHeadphones" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let headphonePorts: Set<AVAudioSession.Port> = [
        .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio,
      ]
      let isConnected = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
        headphonePorts.contains($0.portType)
      }
      result(isConnected)
    }
    */
  }
}

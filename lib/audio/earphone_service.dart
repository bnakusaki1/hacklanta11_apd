import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EarphoneService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.adp/audio_devices',
  );

  final StreamController<void> _mediaButtonController =
      StreamController<void>.broadcast();

  EarphoneService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'mediaButton') {
        debugPrint('HEADSET_DART_RECEIVED ${call.arguments}');
        _mediaButtonController.add(null);
      }
    });
  }

  Stream<void> get mediaButtonStream => _mediaButtonController.stream;

  Future<void> setMediaButtonActive(bool active) async {
    try {
      final nativeActive = await _channel.invokeMethod<bool>(
        'setMediaButtonActive',
        active,
      );
      debugPrint(
        'HEADSET MEDIA BUTTON SESSION: requested=$active '
        'nativeActive=$nativeActive',
      );
    } on PlatformException catch (error) {
      debugPrint('HEADSET MEDIA BUTTON SESSION ERROR: $error');
    } on MissingPluginException {
      debugPrint('HEADSET MEDIA BUTTON SESSION: plugin unavailable');
    }
  }

  /// PUBLIC FUNCTION
  ///
  /// Returns true when a supported earphone/headphone
  /// output is currently connected.
  ///
  /// Example:
  ///
  /// final connected = await earphoneService.hasEarphones();
  Future<bool> hasEarphones() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasEarphones');

      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> dispose() async {
    await setMediaButtonActive(false);
    _channel.setMethodCallHandler(null);
    await _mediaButtonController.close();
  }
}

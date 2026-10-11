import 'package:flutter/services.dart';

class EarphoneService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.adp/audio_devices',
  );

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
}

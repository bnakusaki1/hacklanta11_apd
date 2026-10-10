import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackendConnectionStore {
  static const _urlKey = 'transcription_backend_url';
  static const _tokenKey = 'transcription_backend_access_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String?> readUrl() => _storage.read(key: _urlKey);

  static Future<String?> readAccessToken() => _storage.read(key: _tokenKey);

  static Future<void> save({
    required String url,
    required String accessToken,
  }) async {
    await _storage.write(key: _urlKey, value: url.trim());
    if (accessToken.trim().isEmpty) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: accessToken.trim());
    }
  }
}

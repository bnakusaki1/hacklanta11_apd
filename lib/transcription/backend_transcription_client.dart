import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class TranscriptionBackendClient {
  TranscriptionBackendClient({
    required this.onTranscript,
    required this.onStatus,
    required this.onError,
  });

  final void Function(String text, {required bool isFinal}) onTranscript;
  final void Function(String status) onStatus;
  final void Function(String message) onError;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _relayClosed;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  Future<void> connect({required String url, String? accessToken}) async {
    if (isConnected) return;
    try {
      final uri = Uri.parse(url.trim());
      if (uri.scheme != 'ws' && uri.scheme != 'wss') {
        throw const FormatException(
          'Backend URL must start with ws:// or wss://.',
        );
      }
      final headers = <String, dynamic>{};
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
      onStatus('Connecting to backend…');
      _socket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(const Duration(seconds: 5));
      _relayClosed = Completer<void>();
      _subscription = _socket!.listen(
        _handleMessage,
        onError: (Object error) {
          onStatus('Disconnected');
          onError('Connection to transcription backend failed: $error');
        },
        onDone: () {
          onStatus('Disconnected');
        },
      );
      // The completed websocket handshake confirms the backend accepted the
      // connection. Do not wait for a relay_ready event before starting capture.
      onStatus('Backend connected; starting transcription service…');
    } catch (error) {
      await _subscription?.cancel();
      _subscription = null;
      final socket = _socket;
      _socket = null;
      if (socket?.readyState == WebSocket.open ||
          socket?.readyState == WebSocket.connecting) {
        await socket?.close();
      }
      onStatus('Disconnected');
      onError('Could not connect to transcription backend: $error');
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;
    try {
      final event = jsonDecode(message) as Map<String, dynamic>;
      switch (event['message_type']) {
        case 'relay_ready':
          onStatus('Backend connected; starting transcription service…');
        case 'session_started':
          onStatus('Connected to transcription service.');
        case 'partial_transcript':
        case 'final_transcript':
        case 'final_transcript_with_timestamps':
          onTranscript(event['text'] as String? ?? '', isFinal: false);
        case 'committed_transcript':
        case 'committed_transcript_with_timestamps':
          onTranscript(event['text'] as String? ?? '', isFinal: true);
        case 'relay_closed':
          if (!(_relayClosed?.isCompleted ?? true)) _relayClosed!.complete();
          onStatus('Disconnected');
        case 'error':
        case 'rate_limited':
          final message =
              event['error'] as String? ?? 'Transcription service error.';
          onError(message);
        default:
          break;
      }
    } catch (error) {
      onError('Received an invalid message from transcription backend: $error');
    }
  }

  /// Sends mono 16 kHz PCM16 chunks to the backend websocket relay.
  void sendAudioChunk(Uint8List chunk) {
    if (!isConnected) {
      throw StateError('Transcription backend is not connected.');
    }
    _socket!.add(chunk);
  }

  Future<void> stop() async {
    final socket = _socket;
    if (socket == null) return;
    if (socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({'type': 'stop'}));
      try {
        await _relayClosed?.future.timeout(const Duration(milliseconds: 2300));
      } on TimeoutException {
        // The backend closes the upstream session after committing the final segment.
      }
    }
    await _subscription?.cancel();
    _subscription = null;
    if (socket.readyState == WebSocket.open ||
        socket.readyState == WebSocket.connecting) {
      await socket.close();
    }
    _socket = null;
    onStatus('Disconnected');
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class TranscriptWord {
  final String text;
  final double? start;
  final double? end;

  const TranscriptWord({required this.text, this.start, this.end});

  factory TranscriptWord.fromJson(Map<String, dynamic> json) {
    return TranscriptWord(
      text: json['text']?.toString() ?? '',
      start: (json['start'] as num?)?.toDouble(),
      end: (json['end'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'text': text, 'start': start, 'end': end};
  }
}

class TranscriptSegment {
  final String text;
  final List<TranscriptWord> words;

  const TranscriptSegment({required this.text, required this.words});

  double? get start {
    for (final word in words) {
      if (word.start != null) {
        return word.start;
      }
    }

    return null;
  }

  double? get end {
    for (final word in words.reversed) {
      if (word.end != null) {
        return word.end;
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'start': start,
      'end': end,
      'words': words.map((word) => word.toJson()).toList(),
    };
  }
}

class TranscriptionService {
  WebSocketChannel? _channel;
  StreamSubscription? _messageSubscription;

  Completer<void>? _finalCommitCompleter;

  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();

  final StreamController<String> _partialTranscriptController =
      StreamController<String>.broadcast();

  final StreamController<TranscriptSegment> _committedSegmentController =
      StreamController<TranscriptSegment>.broadcast();

  final List<TranscriptSegment> _segments = [];

  String _partialTranscript = '';
  bool _isConnected = false;
  int _sentChunkCount = 0;
  int _sentByteCount = 0;
  int _partialCount = 0;
  int _committedCount = 0;

  Stream<String> get transcriptStream => _transcriptController.stream;

  Stream<String> get partialTranscriptStream =>
      _partialTranscriptController.stream;

  Stream<TranscriptSegment> get committedSegmentStream =>
      _committedSegmentController.stream;

  List<TranscriptSegment> get segments => List.unmodifiable(_segments);

  String get partialTranscript => _partialTranscript;

  bool get isConnected => _isConnected;

  int get sentChunkCount => _sentChunkCount;

  String get fullTranscript =>
      _segments.map((segment) => segment.text).join(' ').trim();

  Map<String, dynamic> get group2Payload {
    return {
      'full_text': fullTranscript,
      'segments': _segments.map((segment) => segment.toJson()).toList(),
    };
  }

  Future<void> connect() async {
    _segments.clear();
    _partialTranscript = '';
    _finalCommitCompleter = null;
    _isConnected = false;
    _sentChunkCount = 0;
    _sentByteCount = 0;
    _partialCount = 0;
    _committedCount = 0;

    final channel = IOWebSocketChannel.connect(
      Uri.parse('wss://hacklanta-apd-backend.onrender.com/transcribe'),
    );

    await channel.ready;

    _channel = channel;
    _isConnected = true;

    _messageSubscription = channel.stream.listen(
      (message) {
        if (message is! String) {
          return;
        }

        try {
          final decoded = jsonDecode(message);

          if (decoded is! Map) {
            return;
          }

          final data = Map<String, dynamic>.from(decoded);

          final messageType = data['message_type']?.toString();

          final text = data['text']?.toString() ?? '';

          if (messageType == 'partial_transcript') {
            _partialCount++;
            _partialTranscript = text;

            _partialTranscriptController.add(text);

            debugPrint('PARTIAL TRANSCRIPT #$_partialCount: $text');

            return;
          }

          if (messageType == 'committed_transcript_with_timestamps') {
            _committedCount++;
            final rawWords = data['words'];

            final words = <TranscriptWord>[];

            if (rawWords is List) {
              for (final rawWord in rawWords) {
                if (rawWord is Map) {
                  words.add(
                    TranscriptWord.fromJson(Map<String, dynamic>.from(rawWord)),
                  );
                }
              }
            }

            if (text.isNotEmpty) {
              final segment = TranscriptSegment(text: text, words: words);

              _segments.add(segment);

              _committedSegmentController.add(segment);

              _partialTranscript = '';

              _partialTranscriptController.add('');

              _transcriptController.add(fullTranscript);

              debugPrint(
                'COMMITTED TIMESTAMPED #$_committedCount: '
                '${segment.start} -> '
                '${segment.end}: $text',
              );

              debugPrint('FULL TRANSCRIPT: $fullTranscript');

              debugPrint(
                'GROUP 2 PAYLOAD: '
                '${jsonEncode(group2Payload)}',
              );
            }

            final completer = _finalCommitCompleter;

            if (completer != null && !completer.isCompleted) {
              completer.complete();
            }

            return;
          }

          if (messageType == 'relay_closed') {
            final completer = _finalCommitCompleter;

            if (completer != null && !completer.isCompleted) {
              completer.complete();
            }

            return;
          }

          if (messageType == 'error') {
            debugPrint('TRANSCRIPTION ERROR: ${data['error']}');

            final completer = _finalCommitCompleter;

            if (completer != null && !completer.isCompleted) {
              completer.complete();
            }
          }
        } catch (error) {
          debugPrint(
            'Could not parse transcription message: '
            '$error',
          );
        }
      },
      onError: (error) {
        _isConnected = false;
        debugPrint('TRANSCRIPTION SOCKET ERROR: $error');

        final completer = _finalCommitCompleter;

        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      },
      onDone: () {
        _isConnected = false;
        debugPrint('TRANSCRIPTION SOCKET CLOSED');

        final completer = _finalCommitCompleter;

        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      },
    );

    debugPrint('TRANSCRIPTION SOCKET CONNECTED');
  }

  void sendAudio(Uint8List audioChunk) {
    final channel = _channel;
    if (channel == null || !_isConnected) {
      debugPrint('TRANSCRIPTION SEND SKIPPED: socket is not connected');
      return;
    }

    channel.sink.add(audioChunk);
    _sentChunkCount++;
    _sentByteCount += audioChunk.length;

    if (_sentChunkCount == 1 || _sentChunkCount % 50 == 0) {
      debugPrint(
        'TRANSCRIPTION PCM SENT: chunks=$_sentChunkCount | '
        'bytes=$_sentByteCount | socketConnected=$_isConnected',
      );
    }
  }

  /// PUBLIC FUNCTION FOR REPEAT
  ///
  /// Returns the committed transcript words that overlap
  /// the requested recording-time window.
  ///
  /// Example:
  ///
  /// final text = transcriptForTimeRange(
  ///   startSeconds: 15,
  ///   endSeconds: 20,
  /// );
  ///
  /// This does NOT:
  /// - stop the microphone
  /// - stop recording
  /// - disconnect ElevenLabs
  /// - finish the transcription session
  ///
  /// It only reads timestamped words that we already have.
  String transcriptForTimeRange({
    required double startSeconds,
    required double endSeconds,
  }) {
    if (endSeconds <= startSeconds) {
      return '';
    }

    final selectedWords = <String>[];

    for (final segment in _segments) {
      for (final word in segment.words) {
        final wordStart = word.start;
        final wordEnd = word.end;

        if (wordStart == null || wordEnd == null) {
          continue;
        }

        final overlapsWindow =
            wordEnd >= startSeconds && wordStart <= endSeconds;

        if (overlapsWindow && word.text.isNotEmpty) {
          selectedWords.add(word.text);
        }
      }
    }

    return selectedWords.join('').trim();
  }

  /// Convenience function for Repeat.
  ///
  /// Instead of manually calculating the start time,
  /// the caller can provide the current recording time
  /// and the number of seconds requested.
  ///
  /// Example:
  ///
  /// final text = transcriptForRecentSeconds(
  ///   currentSeconds: 37,
  ///   seconds: 10,
  /// );
  ///
  /// This searches the 27s -> 37s transcript window.
  String transcriptForRecentSeconds({
    required double currentSeconds,
    int seconds = 5,
  }) {
    if (seconds != 5 && seconds != 10 && seconds != 20) {
      throw ArgumentError('Repeat duration must be 5, 10, or 20 seconds.');
    }

    if (currentSeconds <= 0) {
      return '';
    }

    final startSeconds = (currentSeconds - seconds)
        .clamp(0.0, currentSeconds)
        .toDouble();

    return transcriptForTimeRange(
      startSeconds: startSeconds,
      endSeconds: currentSeconds,
    );
  }

  Future<void> finishTranscription() async {
    final channel = _channel;

    if (channel == null) {
      return;
    }

    _finalCommitCompleter = Completer<void>();

    debugPrint('REQUESTING FINAL TRANSCRIPT...');

    channel.sink.add(jsonEncode({'type': 'stop'}));

    try {
      await _finalCommitCompleter!.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      debugPrint('FINAL TRANSCRIPT WAIT TIMED OUT');
    }

    debugPrint(
      'FINAL GROUP 2 PAYLOAD: '
      '${jsonEncode(group2Payload)}',
    );
  }

  Future<void> disconnect() async {
    await _messageSubscription?.cancel();

    _messageSubscription = null;

    await _channel?.sink.close();

    _channel = null;
    _isConnected = false;

    _finalCommitCompleter = null;
  }

  Future<void> dispose() async {
    await disconnect();

    await _transcriptController.close();

    await _partialTranscriptController.close();

    await _committedSegmentController.close();
  }
}

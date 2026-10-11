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

  Stream<String> get transcriptStream => _transcriptController.stream;

  Stream<String> get partialTranscriptStream =>
      _partialTranscriptController.stream;

  Stream<TranscriptSegment> get committedSegmentStream =>
      _committedSegmentController.stream;

  List<TranscriptSegment> get segments => List.unmodifiable(_segments);

  String get partialTranscript => _partialTranscript;

  String get fullTranscript =>
      _segments.map((segment) => segment.text).join(' ').trim();

  /// Returns committed transcript words that overlap the selected recording
  /// time window. This only reads transcript data; it does not affect the
  /// active transcription connection.
  String transcriptForTimeRange({
    required double startSeconds,
    required double endSeconds,
  }) {
    if (endSeconds <= startSeconds) return '';

    final selectedWords = <String>[];
    for (final segment in _segments) {
      for (final word in segment.words) {
        final wordStart = word.start;
        final wordEnd = word.end;
        if (wordStart == null ||
            wordEnd == null ||
            wordEnd < startSeconds ||
            wordStart > endSeconds ||
            word.text.isEmpty) {
          continue;
        }
        selectedWords.add(word.text);
      }
    }

    return selectedWords.join().trim();
  }

  /// Convenience lookup for the latest 5, 10, or 20 seconds of recording.
  String transcriptForRecentSeconds({
    required double currentSeconds,
    int seconds = 5,
  }) {
    if (seconds != 5 && seconds != 10 && seconds != 20) {
      throw ArgumentError('Repeat duration must be 5, 10, or 20 seconds.');
    }
    if (currentSeconds <= 0) return '';

    final startSeconds = (currentSeconds - seconds)
        .clamp(0.0, currentSeconds)
        .toDouble();
    final transcript = transcriptForTimeRange(
      startSeconds: startSeconds,
      endSeconds: currentSeconds,
    );
    if (transcript.isNotEmpty) return transcript;

    // The transcription service can be a few seconds behind the microphone,
    // and some committed messages may not include word timestamps. In either
    // case, still show the latest available transcript instead of claiming
    // that none exists.
    final partial = _partialTranscript.trim();
    if (partial.isNotEmpty) return partial;

    for (final segment in _segments.reversed) {
      final text = segment.text.trim();
      if (text.isNotEmpty) return text;
    }

    return '';
  }

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

    final channel = IOWebSocketChannel.connect(
      Uri.parse('wss://hacklanta-apd-backend.onrender.com/transcribe'),
    );

    await channel.ready;

    _channel = channel;

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
            _partialTranscript = text;

            _partialTranscriptController.add(text);

            debugPrint('PARTIAL TRANSCRIPT: $text');

            return;
          }

          if (messageType == 'committed_transcript_with_timestamps') {
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
                'COMMITTED TIMESTAMPED: '
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
        debugPrint('TRANSCRIPTION SOCKET ERROR: $error');

        final completer = _finalCommitCompleter;

        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      },
      onDone: () {
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
    _channel?.sink.add(audioChunk);
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

    _finalCommitCompleter = null;
  }

  Future<void> dispose() async {
    await disconnect();

    await _transcriptController.close();
    await _partialTranscriptController.close();
    await _committedSegmentController.close();
  }
}

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class RepeatAudioService {
  RepeatAudioService({this.maxBufferSeconds = 20}) {
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      debugPrint('REPEAT PLAYBACK STATE: $state');
    });

    _playerCompleteSubscription = _player.onPlayerComplete.listen((_) {
      debugPrint('REPEAT PLAYBACK COMPLETED');
    });
  }

  final int maxBufferSeconds;

  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _bitsPerSample = 16;
  static const int _bytesPerSecond =
      _sampleRate * _channels * (_bitsPerSample ~/ 8);

  final ListQueue<Uint8List> _chunks = ListQueue<Uint8List>();
  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<void> _playerCompleteSubscription;

  int _bufferedBytes = 0;
  bool _audioContextConfigured = false;

  int get _maxBytes => _bytesPerSecond * maxBufferSeconds;

  bool get hasAudio => _bufferedBytes > 0;

  /// Feed microphone PCM chunks into the rolling buffer.
  void addAudioChunk(Uint8List chunk) {
    final copy = Uint8List.fromList(chunk);
    _chunks.addLast(copy);
    _bufferedBytes += copy.length;

    while (_bufferedBytes > _maxBytes && _chunks.isNotEmpty) {
      final removed = _chunks.removeFirst();
      _bufferedBytes -= removed.length;
    }
  }

  /// PUBLIC FUNCTION
  ///
  /// Examples:
  ///
  /// await repeatRecent();             // last 5 seconds
  /// await repeatRecent(seconds: 10);  // last 10 seconds
  /// await repeatRecent(seconds: 20);  // last 20 seconds
  Future<void> repeatRecent({int seconds = 5}) async {
    if (seconds != 5 && seconds != 10 && seconds != 20) {
      throw ArgumentError('Repeat duration must be 5, 10, or 20 seconds.');
    }

    if (_chunks.isEmpty) {
      throw StateError('There is no recent audio to repeat yet.');
    }

    final requestedBytes = _bytesPerSecond * seconds;
    final bytesToUse = math.min(requestedBytes, _bufferedBytes);
    final pcm = Uint8List(bytesToUse);
    var writePosition = bytesToUse;

    for (final chunk in _chunks.toList().reversed) {
      if (writePosition <= 0) {
        break;
      }

      final amountToCopy = math.min(chunk.length, writePosition);
      final sourceStart = chunk.length - amountToCopy;
      writePosition -= amountToCopy;

      pcm.setRange(
        writePosition,
        writePosition + amountToCopy,
        chunk,
        sourceStart,
      );
    }

    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, _wavHeader(pcm.length));
    wav.setRange(44, wav.length, pcm);

    if (!_audioContextConfigured) {
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioMode: AndroidAudioMode.normal,
          ),
        ),
      );
      _audioContextConfigured = true;
    }

    debugPrint(
      'REPEAT PLAYBACK START: requestedSeconds=$seconds | '
      'pcmBytes=${pcm.length} | audioFocus=none',
    );
    await _player.stop();
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  /// Compatibility function.
  /// Existing code that calls repeatLast() will still work
  /// and will now repeat the default 5 seconds.
  Future<void> repeatLast() {
    return repeatRecent();
  }

  Future<void> stopRepeat() async {
    debugPrint('REPEAT PLAYBACK STOP REQUESTED');
    await _player.stop();
  }

  void clear() {
    _chunks.clear();
    _bufferedBytes = 0;
  }

  Uint8List _wavHeader(int audioLength) {
    const headerLength = 44;
    final header = ByteData(headerLength);

    void writeTag(int offset, String tag) {
      for (var i = 0; i < tag.length; i++) {
        header.setUint8(offset + i, tag.codeUnitAt(i));
      }
    }

    writeTag(0, 'RIFF');
    header.setUint32(4, 36 + audioLength, Endian.little);
    writeTag(8, 'WAVE');
    writeTag(12, 'fmt ');

    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, _channels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _bytesPerSecond, Endian.little);
    header.setUint16(32, _channels * (_bitsPerSample ~/ 8), Endian.little);
    header.setUint16(34, _bitsPerSample, Endian.little);

    writeTag(36, 'data');
    header.setUint32(40, math.min(audioLength, 0xffffffff), Endian.little);

    return header.buffer.asUint8List();
  }

  Future<void> dispose() async {
    await _playerStateSubscription.cancel();
    await _playerCompleteSubscription.cancel();
    await _player.dispose();
    clear();
  }
}

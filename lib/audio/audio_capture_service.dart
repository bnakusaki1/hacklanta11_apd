import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();

  // One broadcast controller per recording session. The recorder's own stream
  // is single-subscription, so we listen to it exactly once and fan the chunks
  // out to the file and to any number of listeners (the websocket client).
  StreamController<Uint8List>? _controller;
  StreamSubscription<Uint8List>? _recorderSubscription;
  Completer<void>? _recorderDone;
  IOSink? _audioFileSink;
  String? _currentFilePath;

  Stream<Uint8List>? get audioStream => _controller?.stream;

  String? get currentFilePath => _currentFilePath;

  bool get isCapturing => _controller != null;

  Future<void> startCapture() async {
    if (isCapturing || await _recorder.isRecording()) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission was not granted.');
    }

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${directory.path}/apd_recording_$timestamp.pcm';

    final controller = StreamController<Uint8List>.broadcast();
    final done = Completer<void>();

    try {
      final sink = File(path).openWrite();
      _audioFileSink = sink;
      _currentFilePath = path;
      _controller = controller;
      _recorderDone = done;

      // Must match what the backend expects: 16 kHz, mono, 16-bit PCM
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      final recorderStream = await _recorder.startStream(config);

      _recorderSubscription = recorderStream.listen(
        (chunk) {
          // Write locally, then publish to listeners
          _audioFileSink?.add(chunk);
          if (!controller.isClosed) controller.add(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Roll back so the next attempt starts clean
      await _recorderSubscription?.cancel();
      _recorderSubscription = null;
      try {
        if (await _recorder.isRecording()) await _recorder.stop();
      } catch (_) {}
      await _audioFileSink?.close();
      _audioFileSink = null;
      await controller.close();
      _controller = null;
      _recorderDone = null;
      _currentFilePath = null;
      rethrow;
    }
  }

  /// Stops the microphone, closes the file, and returns the saved file path
  /// (or null if nothing was being recorded).
  Future<String?> stopCapture() async {
    final controller = _controller;
    if (controller == null) return null;

    // Stop the recorder first so it emits any buffered audio and then ends
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}

    // Give the final chunks a moment to arrive before cutting the subscription
    final done = _recorderDone;
    if (done != null) {
      await done.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }

    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
    _recorderDone = null;

    await _audioFileSink?.flush();
    await _audioFileSink?.close();
    _audioFileSink = null;

    _controller = null;
    if (!controller.isClosed) await controller.close();

    return _currentFilePath;
  }

  Future<void> dispose() async {
    await stopCapture();
    await _recorder.dispose();
  }
}
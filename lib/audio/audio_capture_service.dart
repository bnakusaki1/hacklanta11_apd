import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();

  Stream<Uint8List>? _audioStream;
  IOSink? _audioFileSink;
  String? _currentFilePath;

  Stream<Uint8List>? get audioStream => _audioStream;

  String? get currentFilePath => _currentFilePath;

  Future<void> startCapture() async {
    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      throw Exception('Microphone permission was not granted.');
    }

    final directory = await getApplicationDocumentsDirectory();

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    _currentFilePath = '${directory.path}/apd_recording_$timestamp.pcm';

    final file = File(_currentFilePath!);
    _audioFileSink = file.openWrite();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );

    _audioStream = await _recorder.startStream(config);

    _audioStream!.listen((chunk) {
      _audioFileSink?.add(chunk);
    });
  }

  Future<String?> stopCapture() async {
    await _recorder.stop();

    await _audioFileSink?.flush();
    await _audioFileSink?.close();

    _audioFileSink = null;
    _audioStream = null;

    return _currentFilePath;
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    await _audioFileSink?.close();
  }
}

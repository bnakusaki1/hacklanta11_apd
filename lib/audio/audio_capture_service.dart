import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();

  Stream<Uint8List>? _audioStream;
  IOSink? _audioFileSink;
  String? _currentFilePath;
  int _chunkCount = 0;
  int _byteCount = 0;

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
      audioInterruption: AudioInterruptionMode.none,
      androidConfig: AndroidRecordConfig(
        manageBluetooth: false,
        audioSource: AndroidAudioSource.mic,
      ),
    );

    _audioStream = (await _recorder.startStream(config)).asBroadcastStream();
    _chunkCount = 0;
    _byteCount = 0;

    debugPrint(
      'AUDIO CAPTURE STARTED: PCM16 16 kHz mono | '
      'interruption handling: none | Android input: phone mic',
    );

    _audioStream!.listen((chunk) {
      _audioFileSink?.add(chunk);
      _chunkCount++;
      _byteCount += chunk.length;

      if (_chunkCount == 1 || _chunkCount % 50 == 0) {
        debugPrint(
          'AUDIO CAPTURE ACTIVE: chunks=$_chunkCount | bytes=$_byteCount',
        );
      }
    });
  }

  Future<String?> stopCapture() async {
    debugPrint(
      'AUDIO CAPTURE STOP REQUESTED: chunks=$_chunkCount | bytes=$_byteCount',
    );
    await _recorder.stop();

    await _audioFileSink?.flush();
    await _audioFileSink?.close();

    _audioFileSink = null;
    _audioStream = null;

    final pcmPath = _currentFilePath;
    if (pcmPath == null) return null;

    final pcmFile = File(pcmPath);
    final audioLength = await pcmFile.length();
    final wavPath = pcmPath.replaceFirst(RegExp(r'\.pcm$'), '.wav');
    final wavSink = File(wavPath).openWrite();
    try {
      wavSink.add(_wavHeader(audioLength));
      await wavSink.addStream(pcmFile.openRead());
      await wavSink.flush();
    } finally {
      await wavSink.close();
    }
    await pcmFile.delete();

    _currentFilePath = wavPath;
    return wavPath;
  }

  Uint8List _wavHeader(int audioLength) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
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
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeTag(36, 'data');
    header.setUint32(40, math.min(audioLength, 0xffffffff), Endian.little);

    return header.buffer.asUint8List();
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    await _audioFileSink?.close();
  }
}

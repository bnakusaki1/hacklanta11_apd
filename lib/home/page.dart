import 'dart:async';
import 'dart:io';

import 'package:adp/audio/audio_capture_service.dart';
import 'package:adp/audio/transcription_service.dart';
import 'package:adp/settings/page.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioCaptureService _audioService = AudioCaptureService();
  final TranscriptionService _transcriptionService = TranscriptionService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription? _audioSubscription;
  StreamSubscription<String>? _transcriptSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<void>? _completeSubscription;

  bool _isListening = false;
  bool _isPlaying = false;

  int _audioChunksReceived = 0;
  int _audioBytesReceived = 0;

  String? _recordingPath;
  String _liveTranscript = '';

  Duration _playbackPosition = Duration.zero;
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();

    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;

      setState(() {
        _playbackPosition = position;
      });
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;

      setState(() {
        _recordingDuration = duration;
      });
    });

    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _playbackPosition = _recordingDuration;
      });
    });
  }

  Future<void> _startListening() async {
    try {
      await _audioPlayer.stop();

      // Connect Flutter to our local transcription backend.
      await _transcriptionService.connect();

      // Listen for transcript messages coming back from the backend.
      _transcriptSubscription = _transcriptionService.transcriptStream.listen((
        text,
      ) {
        debugPrint('LIVE TRANSCRIPT: $text');

        if (!mounted) return;

        setState(() {
          _liveTranscript = text;
        });
      });

      // Start the existing microphone capture.
      await _audioService.startCapture();

      if (mounted) {
        setState(() {
          _recordingPath = null;
          _liveTranscript = '';
          _playbackPosition = Duration.zero;
          _recordingDuration = Duration.zero;
          _audioChunksReceived = 0;
          _audioBytesReceived = 0;
        });
      }

      // Send every microphone chunk to the transcription backend.
      _audioSubscription = _audioService.audioStream?.listen((audioChunk) {
        _transcriptionService.sendAudio(audioChunk);

        if (!mounted) return;

        setState(() {
          _audioChunksReceived++;
          _audioBytesReceived += audioChunk.length;
        });

        debugPrint(
          'MIC AUDIO: ${audioChunk.length} bytes '
          '| Total chunks: $_audioChunksReceived',
        );
      });

      if (!mounted) return;

      setState(() {
        _isListening = true;
      });
    } catch (error) {
      debugPrint('START LISTENING ERROR: $error');

      await _transcriptSubscription?.cancel();
      _transcriptSubscription = null;

      await _transcriptionService.disconnect();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start listening: $error')),
      );
    }
  }

  Future<void> _stopListening() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    await _transcriptSubscription?.cancel();
    _transcriptSubscription = null;

    await _transcriptionService.disconnect();

    try {
      final savedPath = await _audioService.stopCapture();

      debugPrint('AUDIO SAVED LOCALLY: $savedPath');

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _recordingPath = savedPath;
        _playbackPosition = Duration.zero;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isListening = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save recording: $error')),
      );
    }
  }

  Future<void> _togglePlayback() async {
    final path = _recordingPath;

    if (path == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_recordingDuration > Duration.zero &&
            _playbackPosition >= _recordingDuration) {
          await _audioPlayer.seek(Duration.zero);
        }

        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play recording: $error')),
      );
    }
  }

  Future<void> _seekPlayback(double value) async {
    final durationMs = _recordingDuration.inMilliseconds;

    if (durationMs <= 0) return;

    await _audioPlayer.seek(
      Duration(milliseconds: (durationMs * value).round()),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');

    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    unawaited(_audioSubscription?.cancel());
    unawaited(_transcriptSubscription?.cancel());

    unawaited(_playerStateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_completeSubscription?.cancel());

    unawaited(_transcriptionService.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_audioService.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            label: const Text('Settings'),
            icon: const Icon(Iconsax.setting),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isListening ? Icons.mic : Icons.mic_none, size: 72),

                const SizedBox(height: 20),

                Text(
                  _isListening ? 'Listening...' : 'Microphone stopped',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),

                const SizedBox(height: 12),

                Text('Audio chunks received: $_audioChunksReceived'),

                Text('Audio bytes received: $_audioBytesReceived'),

                const SizedBox(height: 20),

                if (_liveTranscript.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live transcript',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(_liveTranscript),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 30),

                FilledButton.icon(
                  onPressed: _isListening ? _stopListening : _startListening,
                  icon: Icon(_isListening ? Icons.stop : Icons.mic),
                  label: Text(
                    _isListening ? 'STOP LISTENING' : 'START LISTENING',
                  ),
                ),

                if (_recordingPath != null) ...[
                  const SizedBox(height: 28),
                  _buildRecordingCard(Theme.of(context)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingCard(ThemeData theme) {
    final path = _recordingPath!;
    final durationMs = _recordingDuration.inMilliseconds;

    final progress = durationMs <= 0
        ? 0.0
        : (_playbackPosition.inMilliseconds / durationMs)
              .clamp(0.0, 1.0)
              .toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.audio_file, color: theme.colorScheme.primary),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your recording',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        File(path).uri.pathSegments.last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                IconButton.filledTonal(
                  onPressed: _togglePlayback,
                  tooltip: _isPlaying ? 'Pause recording' : 'Play recording',
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ],
            ),

            Slider(
              value: progress,
              onChanged: durationMs > 0 ? _seekPlayback : null,
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_playbackPosition)),
                Text(_formatDuration(_recordingDuration)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:adp/audio/audio_capture_service.dart';
import 'package:adp/audio/earphone_service.dart';
import 'package:adp/audio/repeat_audio_service.dart';
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

  final RepeatAudioService _repeatService = RepeatAudioService(
    maxBufferSeconds: 20,
  );

  final EarphoneService _earphoneService = EarphoneService();

  final TranscriptionService _transcriptionService = TranscriptionService();

  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription? _audioSubscription;

  StreamSubscription<String>? _partialTranscriptSubscription;
  StreamSubscription<String>? _fullTranscriptSubscription;
  StreamSubscription<TranscriptSegment>? _segmentSubscription;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<void>? _completeSubscription;

  bool _isListening = false;
  bool _isPlaying = false;
  bool _isStopping = false;
  bool _isRepeating = false;

  int _audioChunksReceived = 0;
  int _audioBytesReceived = 0;

  String? _recordingPath;

  String _partialTranscript = '';
  String _fullTranscript = '';

  // Repeat result that is ALWAYS shown in the UI.
  String _repeatTranscript = '';
  int _repeatTranscriptSeconds = 5;

  // Lets the UI explain whether audio was also played.
  bool? _repeatUsedEarphones;

  final List<TranscriptSegment> _segments = [];

  Duration _playbackPosition = Duration.zero;
  Duration _recordingDuration = Duration.zero;

  // PCM16 + 16 kHz + mono:
  //
  // 16000 samples/sec * 2 bytes/sample = 32000 bytes/sec.
  static const double _audioBytesPerSecond = 32000.0;

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
      await _repeatService.stopRepeat();

      // Every new session starts with an empty Repeat buffer.
      _repeatService.clear();

      await _transcriptionService.connect();

      _partialTranscriptSubscription = _transcriptionService
          .partialTranscriptStream
          .listen((text) {
            debugPrint('LIVE PARTIAL UI: $text');

            if (!mounted) return;

            setState(() {
              _partialTranscript = text;
            });
          });

      _fullTranscriptSubscription = _transcriptionService.transcriptStream
          .listen((text) {
            debugPrint('FULL TRANSCRIPT UI: $text');

            if (!mounted) return;

            setState(() {
              _fullTranscript = text;
            });
          });

      _segmentSubscription = _transcriptionService.committedSegmentStream
          .listen((segment) {
            debugPrint(
              'TIMESTAMPED SEGMENT UI: '
              '${segment.start} -> ${segment.end}: ${segment.text}',
            );

            if (!mounted) return;

            setState(() {
              _segments.add(segment);
            });
          });

      await _audioService.startCapture();

      if (mounted) {
        setState(() {
          _recordingPath = null;

          _partialTranscript = '';
          _fullTranscript = '';
          _segments.clear();

          _repeatTranscript = '';
          _repeatTranscriptSeconds = 5;
          _repeatUsedEarphones = null;

          _playbackPosition = Duration.zero;
          _recordingDuration = Duration.zero;

          _audioChunksReceived = 0;
          _audioBytesReceived = 0;

          _isListening = true;
          _isStopping = false;
          _isRepeating = false;
        });
      }

      // IMPORTANT:
      //
      // The same microphone stream continuously goes to:
      //
      // 1. ElevenLabs
      // 2. Repeat's rolling 20-second audio buffer
      //
      // Pressing Repeat does NOT cancel this subscription.
      _audioSubscription = _audioService.audioStream?.listen((audioChunk) {
        _transcriptionService.sendAudio(audioChunk);

        _repeatService.addAudioChunk(audioChunk);

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
    } catch (error) {
      debugPrint('START LISTENING ERROR: $error');

      await _audioSubscription?.cancel();
      _audioSubscription = null;

      await _partialTranscriptSubscription?.cancel();
      _partialTranscriptSubscription = null;

      await _fullTranscriptSubscription?.cancel();
      _fullTranscriptSubscription = null;

      await _segmentSubscription?.cancel();
      _segmentSubscription = null;

      await _transcriptionService.disconnect();

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _isStopping = false;
        _isRepeating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start listening: $error')),
      );
    }
  }

  Future<void> _stopListening() async {
    if (_isStopping) return;

    if (mounted) {
      setState(() {
        _isStopping = true;
      });
    }

    try {
      await _audioSubscription?.cancel();
      _audioSubscription = null;

      // Allow ElevenLabs to commit the final words.
      await _transcriptionService.finishTranscription();

      final savedPath = await _audioService.stopCapture();

      debugPrint('AUDIO SAVED LOCALLY: $savedPath');

      debugPrint(
        'FINAL FULL TRANSCRIPT: '
        '${_transcriptionService.fullTranscript}',
      );

      debugPrint(
        'FINAL GROUP 2 DATA: '
        '${_transcriptionService.group2Payload}',
      );

      await _transcriptionService.disconnect();

      await _partialTranscriptSubscription?.cancel();
      _partialTranscriptSubscription = null;

      await _fullTranscriptSubscription?.cancel();
      _fullTranscriptSubscription = null;

      await _segmentSubscription?.cancel();
      _segmentSubscription = null;

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _isStopping = false;

        _recordingPath = savedPath;

        _partialTranscript = '';

        _fullTranscript = _transcriptionService.fullTranscript;

        _playbackPosition = Duration.zero;
      });
    } catch (error) {
      debugPrint('STOP LISTENING ERROR: $error');

      try {
        await _transcriptionService.disconnect();
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _isStopping = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not stop listening: $error')),
      );
    }
  }

  /// PUBLIC REPEAT ACTION USED BY THE UI.
  ///
  /// Behavior:
  ///
  /// 1. Determine the requested recent transcript.
  /// 2. ALWAYS send that transcript to the UI.
  /// 3. Check whether earphones are connected.
  /// 4. If yes, replay the matching recent audio.
  /// 5. If no, do not play audio.
  ///
  /// This function NEVER stops:
  ///
  /// - microphone capture
  /// - ElevenLabs
  /// - the audio subscription
  /// - the recording session
  Future<void> _repeatRecentAudio(int seconds) async {
    if (!_repeatService.hasAudio || _isRepeating || _isStopping) {
      return;
    }

    if (seconds != 5 && seconds != 10 && seconds != 20) {
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isRepeating = true;
        });
      }

      // Because the microphone is PCM16, 16 kHz, mono:
      //
      // 32000 bytes = approximately 1 second.
      //
      // This gives us the current position in the recording.
      final currentSeconds = _audioBytesReceived / _audioBytesPerSecond;

      final recentText = _transcriptionService.transcriptForRecentSeconds(
        currentSeconds: currentSeconds,
        seconds: seconds,
      );

      // EARPHONE CHECK
      final hasEarphones = await _earphoneService.hasEarphones();

      if (!mounted) return;

      // TEXT IS DISPLAYED REGARDLESS OF EARPHONES.
      setState(() {
        _repeatTranscriptSeconds = seconds;
        _repeatUsedEarphones = hasEarphones;

        if (recentText.isEmpty) {
          _repeatTranscript =
              'No committed transcript is available '
              'for the last $seconds seconds yet.';
        } else {
          _repeatTranscript = recentText;
        }
      });

      debugPrint(
        'REPEAT REQUEST: '
        '$seconds sec | '
        'recording time: ${currentSeconds.toStringAsFixed(2)} sec | '
        'earphones: $hasEarphones | '
        'text: $recentText',
      );

      // ONLY play the audio when earphones are connected.
      if (hasEarphones) {
        debugPrint(
          'REPEAT AUDIO: Playing the most recent '
          '$seconds seconds through connected audio output.',
        );

        await _repeatService.repeatRecent(seconds: seconds);
      } else {
        debugPrint(
          'REPEAT AUDIO: No earphones detected. '
          'Showing transcript only.',
        );
      }
    } catch (error) {
      debugPrint('REPEAT ERROR: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not repeat recent conversation: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRepeating = false;
        });
      }
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

  String _formatTimestamp(double? seconds) {
    if (seconds == null) {
      return '--:--';
    }

    final duration = Duration(milliseconds: (seconds * 1000).round());

    final minutes = duration.inMinutes.toString().padLeft(2, '0');

    final remainingSeconds = (duration.inSeconds % 60).toString().padLeft(
      2,
      '0',
    );

    return '$minutes:$remainingSeconds';
  }

  @override
  void dispose() {
    unawaited(_audioSubscription?.cancel());

    unawaited(_partialTranscriptSubscription?.cancel());
    unawaited(_fullTranscriptSubscription?.cancel());
    unawaited(_segmentSubscription?.cancel());

    unawaited(_playerStateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_completeSubscription?.cancel());

    unawaited(_transcriptionService.dispose());
    unawaited(_repeatService.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_audioService.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repeatAvailable =
        _repeatService.hasAudio && !_isRepeating && !_isStopping;

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
                  _isStopping
                      ? 'Finishing transcript...'
                      : _isListening
                      ? 'Listening...'
                      : 'Microphone stopped',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),

                const SizedBox(height: 12),

                Text('Audio chunks received: $_audioChunksReceived'),

                Text('Audio bytes received: $_audioBytesReceived'),

                const SizedBox(height: 20),

                if (_partialTranscript.isNotEmpty)
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
                          Text(_partialTranscript),
                        ],
                      ),
                    ),
                  ),

                if (_fullTranscript.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Full transcript',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(_fullTranscript),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_segments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Timestamped transcript',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final segment in _segments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '[${_formatTimestamp(segment.start)}] '
                                '${segment.text}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                FilledButton.icon(
                  onPressed: _isStopping
                      ? null
                      : _isListening
                      ? _stopListening
                      : _startListening,
                  icon: Icon(_isListening ? Icons.stop : Icons.mic),
                  label: Text(
                    _isStopping
                        ? 'FINISHING...'
                        : _isListening
                        ? 'STOP LISTENING'
                        : 'START LISTENING',
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Repeat recent conversation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),

                const SizedBox(height: 4),

                const Text(
                  'Text is always shown. Audio plays only with earphones.',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 4),

                const Text('5 seconds is the default'),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonal(
                      onPressed: repeatAvailable
                          ? () => _repeatRecentAudio(5)
                          : null,
                      child: const Text('5 SEC'),
                    ),
                    OutlinedButton(
                      onPressed: repeatAvailable
                          ? () => _repeatRecentAudio(10)
                          : null,
                      child: const Text('10 SEC'),
                    ),
                    OutlinedButton(
                      onPressed: repeatAvailable
                          ? () => _repeatRecentAudio(20)
                          : null,
                      child: const Text('20 SEC'),
                    ),
                  ],
                ),

                if (_isRepeating) ...[
                  const SizedBox(height: 8),
                  const Text('Getting recent conversation...'),
                ],

                // REPEAT RESULT
                //
                // This appears regardless of whether earphones
                // are connected.
                if (_repeatTranscript.isNotEmpty) ...[
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.replay),

                              const SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  'Repeat — Last '
                                  '$_repeatTranscriptSeconds seconds',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Text(_repeatTranscript),

                          const SizedBox(height: 10),

                          if (_repeatUsedEarphones == true)
                            const Text(
                              '🎧 Audio replayed through '
                              'connected earphones.',
                            )
                          else if (_repeatUsedEarphones == false)
                            const Text(
                              '🔇 No earphones detected — '
                              'text only.',
                            ),
                        ],
                      ),
                    ),
                  ),
                ],

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

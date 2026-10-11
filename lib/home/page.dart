import 'package:flutter_animate/flutter_animate.dart';

import 'dart:async';
import 'dart:io';

import 'package:adp/audio/audio_capture_service.dart';
import 'package:adp/audio/transcription_service.dart';
import 'package:adp/settings/page.dart';
import 'package:adp/summarization/gemini_conversation_summarizer.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioCaptureService _audioService = AudioCaptureService();
  final TranscriptionService _transcriptionService = TranscriptionService();
  final GeminiConversationSummarizer _summarizer =
      GeminiConversationSummarizer();
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
  bool _isSummarizingHighlight = false;
  bool _isSummarizingConversation = false;

  int _audioChunksReceived = 0;
  int _audioBytesReceived = 0;

  String? _recordingPath;

  String _partialTranscript = '';
  String _fullTranscript = '';
  String _conversationSummary = '';
  String _summaryTitle = 'Conversation summary';
  String? _summaryErrorMessage;
  int _summarySessionId = 0;
  int _summaryRequestId = 0;

  final List<TranscriptSegment> _segments = [];

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

      _summarySessionId++;
      _summaryRequestId++;
      setState(() {
        _conversationSummary = '';
        _summaryTitle = 'Conversation summary';
        _summaryErrorMessage = null;
        _isSummarizingHighlight = false;
        _isSummarizingConversation = false;
      });

      // Connect to our backend / ElevenLabs pipeline.
      await _transcriptionService.connect();

      // LIVE / PARTIAL transcript.
      _partialTranscriptSubscription = _transcriptionService
          .partialTranscriptStream
          .listen((text) {
            debugPrint('LIVE PARTIAL UI: $text');

            if (!mounted) return;

            setState(() {
              _partialTranscript = text;
            });
          });

      // FULL committed transcript.
      _fullTranscriptSubscription = _transcriptionService.transcriptStream
          .listen((text) {
            debugPrint('FULL TRANSCRIPT UI: $text');

            if (!mounted) return;

            setState(() {
              _fullTranscript = text;
            });
          });

      // Timestamped committed segments.
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

      // Start microphone capture.
      await _audioService.startCapture();

      if (mounted) {
        setState(() {
          _recordingPath = null;

          _partialTranscript = '';
          _fullTranscript = '';
          _segments.clear();

          _playbackPosition = Duration.zero;
          _recordingDuration = Duration.zero;

          _audioChunksReceived = 0;
          _audioBytesReceived = 0;

          _isListening = true;
          _isStopping = false;
        });
      }

      // Send every microphone chunk to transcription.
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
      // Stop sending new microphone chunks first.
      await _audioSubscription?.cancel();
      _audioSubscription = null;

      // IMPORTANT:
      // Tell the backend to commit the final ElevenLabs segment.
      // Keep transcript listeners alive while we wait.
      await _transcriptionService.finishTranscription();

      // Save the audio.
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

      // Only disconnect AFTER the final committed transcript
      // has had a chance to arrive.
      await _transcriptionService.disconnect();

      await _partialTranscriptSubscription?.cancel();
      _partialTranscriptSubscription = null;

      await _fullTranscriptSubscription?.cancel();
      _fullTranscriptSubscription = null;

      await _segmentSubscription?.cancel();
      _segmentSubscription = null;

      final finalTranscript = _transcriptionService.fullTranscript;
      final summarySessionId = _summarySessionId;

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _isStopping = false;

        _recordingPath = savedPath;

        _partialTranscript = '';

        _fullTranscript = _transcriptionService.fullTranscript;

        _playbackPosition = Duration.zero;
      });

      if (finalTranscript.isNotEmpty) {
        unawaited(
          _generateConversationSummary(finalTranscript, summarySessionId),
        );
      }
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

  String get _latestHighlightButtonLabel {
    final latestText = _partialTranscript.trim().isNotEmpty
        ? _partialTranscript.trim()
        : (_segments.isNotEmpty ? _segments.last.text.trim() : '');
    final normalized = latestText.toLowerCase();

    if (normalized.contains('?') ||
        RegExp(
          r'^(what|why|how|who|when|where|which|is|are|am|do|does|did|can|could|would|will|should|have|has|had)\b',
        ).hasMatch(normalized) ||
        normalized.contains('asked a question')) {
      return 'What was the question?';
    }
    if (RegExp(r'\b(decided|agreed|settled on|going with)\b')
        .hasMatch(normalized)) {
      return 'What was decided?';
    }
    if (RegExp(r'\b(next step|action item|follow up|we need to|i will)\b')
        .hasMatch(normalized)) {
      return 'What are the next steps?';
    }
    return 'Summarize the latest highlight';
  }

  String _latestHighlightContext() {
    final recentSegments = _segments.length <= 5
        ? _segments
        : _segments.sublist(_segments.length - 5);
    final lines = recentSegments
        .map((segment) => segment.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final partial = _partialTranscript.trim();
    if (partial.isNotEmpty && (lines.isEmpty || lines.last != partial)) {
      lines.add(partial);
    }
    return lines.join('\n');
  }

  Future<void> _summarizeLatestHighlight() async {
    final contextText = _latestHighlightContext();
    if (contextText.isEmpty || _isSummarizingHighlight) return;

    final summaryTitle = _latestHighlightButtonLabel;
    final sessionId = _summarySessionId;
    final summaryRequestId = ++_summaryRequestId;
    setState(() {
      _isSummarizingHighlight = true;
      _isSummarizingConversation = false;
      _summaryTitle = summaryTitle;
      _summaryErrorMessage = null;
      _conversationSummary = '';
    });

    try {
      final summary = await _summarizer.summarizeHighlight(contextText);
      if (!mounted ||
          sessionId != _summarySessionId ||
          summaryRequestId != _summaryRequestId) {
        return;
      }
      setState(() => _conversationSummary = summary);
    } catch (error) {
      if (!mounted ||
          sessionId != _summarySessionId ||
          summaryRequestId != _summaryRequestId) {
        return;
      }
      setState(() => _summaryErrorMessage = error.toString());
    } finally {
      if (mounted &&
          sessionId == _summarySessionId &&
          summaryRequestId == _summaryRequestId) {
        setState(() => _isSummarizingHighlight = false);
      }
    }
  }

  Future<void> _generateConversationSummary(
    String transcript,
    int sessionId,
  ) async {
    if (transcript.trim().isEmpty || sessionId != _summarySessionId) return;
    final summaryRequestId = ++_summaryRequestId;
    setState(() {
      _isSummarizingHighlight = false;
      _isSummarizingConversation = true;
      _summaryTitle = 'Conversation summary';
      _summaryErrorMessage = null;
      _conversationSummary = '';
    });

    try {
      final summary = await _summarizer.summarizeConversation(transcript);
      if (!mounted ||
          sessionId != _summarySessionId ||
          summaryRequestId != _summaryRequestId) {
        return;
      }
      setState(() => _conversationSummary = summary);
    } catch (error) {
      if (!mounted ||
          sessionId != _summarySessionId ||
          summaryRequestId != _summaryRequestId) {
        return;
      }
      setState(() => _summaryErrorMessage = error.toString());
    } finally {
      if (mounted &&
          sessionId == _summarySessionId &&
          summaryRequestId == _summaryRequestId) {
        setState(() => _isSummarizingConversation = false);
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');

    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
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
    unawaited(_audioPlayer.dispose());
    unawaited(_audioService.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _isStopping
        ? 'FINISHING...'
        : _isListening
        ? 'Stop listening'
        : 'Start listening';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Sonomod',
          style: GoogleFonts.bpmfHuninn(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Color.fromRGBO(247, 252, 242, 1),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const FaIcon(
              FontAwesomeIcons.gear,
              size: 20,
              color: Colors.black,
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color.fromRGBO(231, 244, 217, 1),
              Color.fromRGBO(247, 252, 242, 1),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 1,
                child: ClipRect(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                      stops: [0.0, 1], // fade zone: top 40% of the area
                    ).createShader(bounds),
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: Text(
                          _partialTranscript,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_isSummarizingHighlight ||
                            _isSummarizingConversation ||
                            _conversationSummary.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              // mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _summaryTitle,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_isSummarizingHighlight ||
                                    _isSummarizingConversation)
                                  const CircularProgressIndicator(),
                                if (_conversationSummary.isNotEmpty)
                                  MarkdownBody(
                                    data: _conversationSummary,
                                    styleSheet:
                                        MarkdownStyleSheet.fromTheme(
                                          Theme.of(context),
                                        ).copyWith(
                                          h1: Theme.of(context)
                                              .textTheme
                                              .headlineMedium,
                                          code: const TextStyle(
                                            fontFamily: 'monospace',
                                            backgroundColor: Color(0x11000000),
                                          ),
                                          blockquotePadding:
                                              const EdgeInsets.all(12),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (_summaryErrorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _summaryErrorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 200,
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      fixedSize: const Size(double.maxFinite, 60),
                    ),
                    onPressed:
                        _isSummarizingHighlight || _isSummarizingConversation
                        ? null
                        : _summarizeLatestHighlight,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _isSummarizingHighlight
                          ? 'Summarizing…'
                          : _latestHighlightButtonLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                  .animate(target: _isListening ? 1 : 0)
                  .fadeIn(duration: 250.ms)
                  .scale(duration: 250.ms, curve: Curves.easeInOut),
              SizedBox.shrink()
                  .animate(target: _isListening ? 1 : 0)
                  .custom(
                    duration: 400.ms,
                    curve: Curves.easeInOut,
                    builder: (context, value, _) {
                      final backgroundColor = Color.lerp(
                        Colors.white,
                        Colors.red.shade100,
                        value,
                      )!;
                      final foregroundColor = Color.lerp(
                        Colors.black,
                        Colors.red.shade900,
                        value,
                      )!;

                      return FilledButton.icon(
                        icon: Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: FaIcon(
                            _isStopping
                                ? FontAwesomeIcons.spinner
                                : _isListening
                                ? FontAwesomeIcons.stop
                                : FontAwesomeIcons.microphone,
                            size: 20,
                          ),
                        ),
                        label: AnimatedSwitcher(
                          duration: 250.ms,
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.6,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            label,
                            key: ValueKey(label),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(
                            backgroundColor,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            foregroundColor,
                          ),
                          fixedSize: WidgetStateProperty.all(
                            const Size(double.maxFinite, 60),
                          ),
                        ),
                        onPressed: _isStopping
                            ? null
                            : _isListening
                            ? _stopListening
                            : _startListening,
                      );
                    },
                  ),
            ],
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

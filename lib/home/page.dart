import 'dart:async';
import 'dart:typed_data';

import 'package:adp/audio/audio_capture_service.dart';
import 'package:adp/settings/page.dart';
import 'package:adp/transcription/backend_connection_store.dart';
import 'package:adp/transcription/backend_transcription_client.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TranscriptionBackendClient _client;
  final AudioCaptureService _audioService = AudioCaptureService();
  StreamSubscription<Uint8List>? _audioSubscription;

  bool _isListening = false;
  bool _isConnecting = false;
  bool _isStopping = false;
  int _audioChunksSent = 0;
  int _audioBytesSent = 0;
  String _connectionStatus = 'Microphone stopped';
  String _committedTranscript = '';
  String _partialTranscript = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = TranscriptionBackendClient(
      onTranscript: (text, {required isFinal}) {
        if (!mounted) return;
        setState(() {
          if (isFinal) {
            _committedTranscript = [
              _committedTranscript,
              text,
            ].where((part) => part.isNotEmpty).join(' ');
            _partialTranscript = '';
          } else {
            _partialTranscript = text;
          }
        });
      },
      onStatus: (status) {
        if (mounted) setState(() => _connectionStatus = status);
      },
      onError: (message) {
        if (mounted) setState(() => _errorMessage = message);
      },
    );
  }

Future<void> _startListening() async {
  if (_isConnecting || _isListening) return;

  setState(() {
    _isConnecting = true;
    _errorMessage = null;
    _committedTranscript = '';
    _partialTranscript = '';
    _audioChunksSent = 0;
    _audioBytesSent = 0;
    _connectionStatus = 'Connecting to backend…';
  });

  try {
    // 1. Read the saved backend URL and access token
    final values = await Future.wait([
      BackendConnectionStore.readUrl(),
      BackendConnectionStore.readAccessToken(),
    ]);
    final url = values[0];
    if (url == null || url.isEmpty) {
      throw StateError('Add your apd_backend WebSocket URL in Settings.');
    }

    // 2. Connect to the backend first so no audio is captured before there is
    //    somewhere to send it. The URL must end in /transcribe.
    await _client.connect(url: url, accessToken: values[1]);

    // 3. Start the microphone
    await _audioService.startCapture();
    final audioStream = _audioService.audioStream;
    if (audioStream == null) {
      throw StateError('Microphone audio stream is unavailable.');
    }

    // 4. Flip to listening BEFORE subscribing. The chunk handler checks
    //    _isListening, so setting it afterwards would drop the first chunks.
    _isListening = true;
    if (mounted) {
      setState(() => _connectionStatus = 'Listening and streaming audio');
    }

    // 5. Subscribe immediately: the stream is broadcast, so anything emitted
    //    before this point would be lost.
    _audioSubscription = audioStream.listen(
      (audioChunk) {
        if (!mounted || !_isListening) return;
        try {
          _client.sendAudioChunk(audioChunk);
          setState(() {
            _audioChunksSent++;
            _audioBytesSent += audioChunk.length;
          });
        } catch (error) {
          setState(
            () => _errorMessage = 'Could not send microphone audio: $error',
          );
          unawaited(_stopListening());
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _errorMessage = 'Microphone capture failed: $error');
        }
        unawaited(_stopListening());
      },
      cancelOnError: false,
    );
  } catch (error) {
    // Roll everything back so the next attempt starts clean
    _isListening = false;
    try {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _audioService.stopCapture();
    } catch (_) {
      // best-effort cleanup
    } finally {
      await _client.stop();
    }
    if (mounted) {
      setState(() {
        _connectionStatus = 'Microphone stopped';
        _errorMessage = error.toString();
      });
    }
  } finally {
    if (mounted) setState(() => _isConnecting = false);
  }
}

  Future<void> _stopListening() async {
    if (_isStopping) return;
    if (mounted) setState(() => _isStopping = true);
    try {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      String? savedPath;
      try {
        savedPath = await _audioService.stopCapture();
      } finally {
        // Send stop after the last audio chunk so the backend can commit the tail.
        await _client.stop();
      }
      if (mounted) {
        setState(() {
          _isListening = false;
          _connectionStatus = 'Microphone stopped';
        });
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved on this device.')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not stop recording: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isListening = false;
          _connectionStatus = 'Microphone stopped';
          _isStopping = false;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    if (_isConnecting || _isStopping) return;
    if (_isListening) await _stopListening();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  @override
  void dispose() {
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _audioSubscription?.cancel();
    await _audioService.dispose();
    await _client.stop();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transcript = [
      _committedTranscript,
      _partialTranscript,
    ].where((part) => part.isNotEmpty).join(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
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

              const SizedBox(height: 30),

              FilledButton.icon(
                onPressed: _isListening ? _stopListening : _startListening,
                icon: Icon(_isListening ? Icons.stop : Icons.mic),
                label: Text(
                  _isListening ? 'STOP LISTENING' : 'START LISTENING',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

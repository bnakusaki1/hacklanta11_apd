import 'dart:async';

import 'package:adp/audio/audio_capture_service.dart';
import 'package:adp/settings/page.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioCaptureService _audioService = AudioCaptureService();

  StreamSubscription? _audioSubscription;

  bool _isListening = false;
  int _audioChunksReceived = 0;
  int _audioBytesReceived = 0;

  Future<void> _startListening() async {
    try {
      await _audioService.startCapture();

      _audioSubscription = _audioService.audioStream?.listen((audioChunk) {
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

      setState(() {
        _isListening = true;
      });
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start microphone: $error')),
      );
    }
  }

  Future<void> _stopListening() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    final savedPath = await _audioService.stopCapture();

    debugPrint('AUDIO SAVED LOCALLY: $savedPath');

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _audioService.dispose();
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

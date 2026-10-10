import 'package:adp/settings/page.dart';
import 'package:adp/transcription/backend_connection_store.dart';
import 'package:adp/transcription/backend_transcription_client.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TranscriptionBackendClient _client;
  bool _enabled = true;
  bool _connecting = false;
  String _connectionStatus = 'Not connected';
  String _committedTranscript = '';
  String _partialTranscript = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = TranscriptionBackendClient(
      onTranscript: (text, {required isFinal}) {
        if (!mounted || !_enabled) return;
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
        if (mounted) {
          setState(() {
            _connectionStatus = status;
            if (status == 'Disconnected') _connecting = false;
          });
        }
      },
      onError: (message) {
        if (mounted) setState(() => _errorMessage = message);
      },
    );
    _connectToBackend();
  }

  Future<void> _connectToBackend() async {
    if (!_enabled || _connecting || _client.isConnected) return;
    setState(() {
      _connecting = true;
      _errorMessage = null;
    });
    try {
      final values = await Future.wait([
        BackendConnectionStore.readUrl(),
        BackendConnectionStore.readAccessToken(),
      ]);
      final url = values[0];
      if (url == null || url.isEmpty) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'Add your apd_backend WebSocket URL in Settings.',
          );
        }
        return;
      }
      await _client.connect(url: url, accessToken: values[1]);
    } catch (_) {
      // Detailed connection errors are shown by the client callback.
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _enabled = enabled;
      _errorMessage = null;
      _partialTranscript = '';
      if (!enabled) {
        _committedTranscript = '';
        _connectionStatus = 'Not connected';
      }
    });
    if (enabled) {
      await _connectToBackend();
    } else {
      await _client.stop();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
    if (_enabled) {
      await _client.stop();
      await _connectToBackend();
    }
  }

  @override
  void dispose() {
    _client.stop();
    super.dispose();
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
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Conversation transcript',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Live transcription is relayed through apd_backend and ElevenLabs Scribe.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: SwitchListTile.adaptive(
                  value: _enabled,
                  onChanged: _setEnabled,
                  title: const Text('Live transcription'),
                  subtitle: Text(_enabled ? _connectionStatus : 'Turned off'),
                  secondary: Icon(
                    _connectionStatus.startsWith('Connected')
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: _connectionStatus.startsWith('Connected')
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: _errorMessage != null
                      ? Text(_errorMessage!, style: theme.textTheme.bodyLarge)
                      : transcript.isEmpty
                      ? Center(
                          child: Text(
                            _enabled
                                ? 'Waiting for audio input…'
                                : 'Transcription is off.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          reverse: true,
                          child: Text(
                            transcript,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Audio capture is not connected yet. Audio chunks can be sent through the transcription client when capture is merged.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

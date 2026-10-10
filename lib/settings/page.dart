import 'package:adp/transcription/backend_connection_store.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _accessTokenController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final values = await Future.wait([
      BackendConnectionStore.readUrl(),
      BackendConnectionStore.readAccessToken(),
    ]);
    if (!mounted) return;
    _urlController.text = values[0] ?? '';
    _accessTokenController.text = values[1] ?? '';
    setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    final uri = Uri.tryParse(_urlController.text.trim());
    if (uri == null ||
        !['ws', 'wss'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid ws:// or wss:// backend URL.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await BackendConnectionStore.save(
        url: _urlController.text,
        accessToken: _accessTokenController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backend settings saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save backend settings.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _accessTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back to Home',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Transcription backend',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to apd_backend. The ElevenLabs API key stays on the server in its .env file.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlController,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Backend WebSocket URL',
                    hintText: 'ws://192.168.1.20:3000/transcribe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _accessTokenController,
                  obscureText: !_showToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Backend access token',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _showToken ? 'Hide token' : 'Show token',
                      onPressed: () => setState(() => _showToken = !_showToken),
                      icon: Icon(
                        _showToken ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _saveSettings,
                  child: Text(_saving ? 'Saving…' : 'Save backend settings'),
                ),
              ],
            ),
    );
  }
}

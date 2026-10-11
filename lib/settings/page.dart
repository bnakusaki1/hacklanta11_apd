import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // UI prototype only. This value is not connected to sound processing yet.
  bool _backgroundSoundLocalizationEnabled = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back to Home',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Audio', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              value: _backgroundSoundLocalizationEnabled,
              onChanged: (enabled) {
                setState(() {
                  _backgroundSoundLocalizationEnabled = enabled;
                });
              },
              secondary: Icon(
                Icons.spatial_audio_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Background sound localization'),
            ),
          ),
        ],
      ),
    );
  }
}

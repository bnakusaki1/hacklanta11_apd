import 'package:adp/home/page.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  bool _requestingPermission = false;

  static const _steps = <_OnboardingStep>[
    _OnboardingStep(
      icon: Icons.mic_none_rounded,
      title: 'Let’s talk about audio',
      description:
          'Hacklanta uses your microphone to capture audio for your focus sessions. Audio is only recorded when you choose to start a session.',
      permission: _OnboardingPermission.microphone,
    ),
    _OnboardingStep(
      icon: Icons.headphones_rounded,
      title: 'Keep a session going',
      description:
          'Allow background activity so an active focus session can continue when you switch apps or lock your screen. On iPhone, background audio is managed by iOS and does not have a separate permission prompt.',
      permission: _OnboardingPermission.backgroundActivity,
    ),
    _OnboardingStep(
      icon: Icons.notifications_none_rounded,
      title: 'Stay in the loop',
      description:
          'Notifications can let you know about your focus sessions and reminders. You can change this choice later in your device settings.',
      permission: _OnboardingPermission.notifications,
    ),
  ];

  Future<void> _continue() async {
    if (_requestingPermission) return;

    setState(() => _requestingPermission = true);
    try {
      switch (_steps[_step].permission) {
        case _OnboardingPermission.microphone:
          await Permission.microphone.request();
        case _OnboardingPermission.backgroundActivity:
          // Android offers a system prompt to exclude the app from battery
          // optimizations. iOS has no equivalent user permission prompt.
          if (Theme.of(context).platform == TargetPlatform.android) {
            await Permission.ignoreBatteryOptimizations.request();
          }
        case _OnboardingPermission.notifications:
          await Permission.notification.request();
      }
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }

    if (!mounted) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Hacklanta')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: (_step + 1) / _steps.length),
              const Spacer(),
              Icon(
                step.icon,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 28),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                step.description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              FilledButton(
                onPressed: _requestingPermission ? null : _continue,
                child: Text(_requestingPermission ? 'Please wait…' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OnboardingPermission { microphone, backgroundActivity, notifications }

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.permission,
  });

  final IconData icon;
  final String title;
  final String description;
  final _OnboardingPermission permission;
}

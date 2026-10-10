import 'package:adp/home/page.dart';
import 'package:flutter/material.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboarding')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const HomePage()),
          ),
          child: const Text('Whereas disregard and contempt for human rights have resulted'),
        ),
      ),
    );
  }
}


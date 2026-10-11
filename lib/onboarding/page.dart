import 'package:adp/home/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();

  int _step = 0;
  bool _requestingPermission = false;

  static const _steps = <_OnboardingStep>[
    _OnboardingStep(
      imagePath: "assets/images/1.jpg",
      title: 'Focus\nBetter',
      bg: const Color.fromRGBO(244, 219, 214, 1),
      description: 'Access smart summaries and intelligent rewinds to instantly catch up on missed conversation details during your focus sessions.',
      permission: _OnboardingPermission.microphone,
    ),
    _OnboardingStep(
      imagePath: "assets/images/1.jpg",
      title: 'Multi\nLingual',
      bg: const Color.fromRGBO(246, 253, 226, 1),
      description: 'Allow background activity so audio filtering and live processing remain uninterrupted across more than 90 supported languages continuously.',
      permission: _OnboardingPermission.backgroundActivity,
    ),
    _OnboardingStep(
      imagePath: "assets/images/1.jpg",
      title: 'Sound\nLocalization',
      bg: const Color.fromRGBO(250, 231, 213, 1),
      description: 'Enable instant notifications to receive real-time directional alerts for critical environmental sounds like sirens or urgent alarms nearby.',
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
      final nextStep = _step + 1;
      await _pageController.animateToPage(
        nextStep,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
      if (!mounted) return;
      if (_step != nextStep) setState(() => _step = nextStep);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      // appBar: AppBar(
      //   title: Center(
      //     child: Text(
      //       'Sonomod',
      //       style: GoogleFonts.bpmfHuninn(fontWeight: FontWeight.bold),
      //     ),
      //   ),
      // ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (value) {
                HapticFeedback.lightImpact();
              },
              children: List.generate(_steps.length, (index) {
                _OnboardingStep step = _steps[index];

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.topLeft,
                  decoration: BoxDecoration(color: step.bg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 100, bottom: 20),
                        child: Text(
                          step.title,
                          style: TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                      Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 150),
                        child: Text(
                          step.description,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            SafeArea(
              child: SizedBox(
                height: 40,
                child: Center(
                  child: SmoothPageIndicator(
                    controller: _pageController,
                    count: _steps.length,
                    effect: WormEffect(
                      dotHeight: 2,
                      dotWidth: (screenWidth - 40 - 20) / (_steps.length),
                      spacing: 10,
                      dotColor: Colors.black.withOpacity(0.2),
                      activeDotColor: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _continue,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      fixedSize: const Size.fromHeight(60),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      _step < _steps.length - 1 ? 'Continue' : 'Get Started',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _OnboardingPermission { microphone, backgroundActivity, notifications }

class _OnboardingStep {
  const _OnboardingStep({
    required this.imagePath,
    required this.bg,
    required this.title,
    required this.description,
    required this.permission,
  });

  final String imagePath;
  final Color bg;
  final String title;
  final String description;
  final _OnboardingPermission permission;
}

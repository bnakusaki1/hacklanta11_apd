import 'package:adp/onboarding/page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _projectBlue = Color(0xFF1D4ED8);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hacklanta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _projectBlue).copyWith(
          primary: _projectBlue,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          fontFamily: GoogleFonts.googleSans().fontFamily,
        ),
      ),
      home: const OnboardingPage(),
    );
  }
}


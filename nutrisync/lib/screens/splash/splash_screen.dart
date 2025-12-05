import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../welcome/welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  double opacity = 0; // Control opacity for fade effect

  @override
  void initState() {
    super.initState();
    
    // Start animation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(milliseconds: 500), () {
        setState(() {
          opacity = 1; // Fade in
        });
      });

      Future.delayed(Duration(milliseconds: 2500), () {
        setState(() {
          opacity = 0; // Fade out
        });
      });

      Future.delayed(Duration(milliseconds: 3000), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => WelcomeScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black, // Same as intro div background
      body: Center(
        child: AnimatedOpacity(
          opacity: opacity,
          duration: Duration(milliseconds: 700), // Smooth fade
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Logo
              DefaultTextStyle(
                style: theme.textTheme.headlineLarge!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                child: AnimatedTextKit(
                  animatedTexts: [
                    TypewriterAnimatedText(
                      'NutriSync',
                      speed: const Duration(milliseconds: 100),
                    ),
                  ],
                  isRepeatingAnimation: false,
                  totalRepeatCount: 1,
                ),
              ),
              const SizedBox(height: 20),
              // Tagline
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(seconds: 1),
                builder: (context, double opacity, child) {
                  return Opacity(opacity: opacity, child: child);
                },
                child: Text(
                  "Your AI Nutrition Assistant",
                  style: theme.textTheme.bodyLarge!.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 40),
              // Loading Indicator
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

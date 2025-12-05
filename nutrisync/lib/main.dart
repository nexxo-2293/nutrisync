import 'package:flutter/material.dart';
import 'package:nutrisync/screens/splash/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutrisync/screens/welcome/welcome_screen.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:nutrisync/widgets/bottom_nav_bar.dart';
import 'package:nutrisync/screens/main/main_screen.dart';
import 'package:camera/camera.dart'; // Added import for camera
import 'package:nutrisync/firebase_options.dart'; // Import your Firebase options
import 'package:flutter/foundation.dart' show kIsWeb; // Import for kIsWeb

// Define light and dark themes
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  colorScheme: ColorScheme.light(
    primary: Color.fromARGB(255, 93, 54, 231), // Vibrant Teal
    secondary: Color.fromARGB(255, 24, 8, 163), // Warm Coral
    surface: Color(0xFFFFFFFF), // Pure White
    background: Color(0xFFF5F5F5), // Light Gray
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Color(0xFF212121), // Dark Gray
  ),
  // Component overrides

  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: Color(0xFFFF5252), // Coral FAB
  ),
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.light,
  colorScheme: ColorScheme.light(
    primary: Color.fromARGB(255, 93, 54, 231), // Vibrant Teal
    secondary: Color.fromARGB(255, 24, 8, 163), // Warm Coral
    surface: Color(0xFFFFFFFF), // Pure White
    background: Color(0xFFF5F5F5), // Light Gray
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Color(0xFF212121), // Dark Gray
  ),
  // Component overrides.

  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: Color(0xFFFF5252), // Coral FAB
  ),
);

/// Global variable for available cameras.
late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize cameras only if not running on web.
  if (!kIsWeb) {
    cameras = await availableCameras();
  } else {
    cameras = []; // Empty list for web
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NutriSync',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system, // Follows system theme
      home: AuthCheck(),
    );
  }
}

class AuthCheck extends StatefulWidget {
  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2)); // Show splash for 2 seconds
    User? user = FirebaseAuth.instance.currentUser;
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => user != null ? MainScreen() : WelcomeScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen(); // Always show SplashScreen first
  }
}

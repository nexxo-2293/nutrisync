import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutrisync/screens/main/main_screen.dart';
import 'package:nutrisync/screens/welcome/welcome_screen.dart';
import 'package:nutrisync/screens/auth/register_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/registration_Details.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  int _passwordConditionCount = 0;
  bool _isPasswordValid = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      _updatePasswordStrength(_passwordController.text);
    });
  }

  void _updatePasswordStrength(String password) {
    int conditionsMet = 0;
    // Condition 1: At least 8 characters
    if (password.length >= 8) conditionsMet++;
    // Condition 2: Contains at least one letter
    if (RegExp(r'[A-Za-z]').hasMatch(password)) conditionsMet++;
    // Condition 3: Contains at least one number
    if (RegExp(r'[0-9]').hasMatch(password)) conditionsMet++;
    // Condition 4: Contains at least one special character
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) conditionsMet++;

    setState(() {
      _passwordConditionCount = conditionsMet;
      _isPasswordValid = (conditionsMet == 4);
    });
  }

  Widget _buildPasswordCriteria(String text, bool conditionMet) {
    return Row(
      children: [
        Icon(
          conditionMet ? Icons.check_circle : Icons.cancel,
          color: conditionMet ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _login() async {
    User? user = await _authService.login(_emailController.text, _passwordController.text);
    if (user != null) {
      _checkUserDetails(user);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login failed")));
    }
  }

  void _googleSignIn() async {
    User? user = await _authService.signInWithGoogle();
    if (user != null) {
      _checkUserDetails(user);
    }
  }

  void _checkUserDetails(User user) async {
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc.data() != null) {
      var data = userDoc.data() as Map<String, dynamic>;
      if (data.containsKey('name') &&
          data.containsKey('age') &&
          data.containsKey('healthConditions')) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => MainScreen()));
        return;
      }
    }

    // If details are missing, navigate to RegistrationDetailsScreen
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) =>
            RegistrationDetailsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(-1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  void _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please enter your email to reset password")));
      return;
    }
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailController.text);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password reset email sent")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 700),
            pageBuilder: (context, animation, secondaryAnimation) =>
                WelcomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(-1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOut;
              var tween = Tween(begin: begin, end: end)
                  .chain(CurveTween(curve: curve));
              return SlideTransition(position: animation.drive(tween), child: child);
            },
          ),
        );
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Welcome Back!",
                          style: theme.textTheme.headlineSmall!
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text("Login to continue", style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 30),
                        TextField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: "Email",
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: "Password",
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        // Password strength indicator
                        if (_passwordController.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: _passwordConditionCount / 4,
                                  backgroundColor: Colors.grey[300],
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 5),
                                Text("$_passwordConditionCount of 4 conditions met"),
                                const SizedBox(height: 10),
                                _buildPasswordCriteria(
                                    "At least 8 characters",
                                    _passwordController.text.length >= 8),
                                _buildPasswordCriteria(
                                    "Contains a letter",
                                    RegExp(r'[A-Za-z]').hasMatch(
                                        _passwordController.text)),
                                _buildPasswordCriteria(
                                    "Contains a number",
                                    RegExp(r'[0-9]').hasMatch(
                                        _passwordController.text)),
                                _buildPasswordCriteria(
                                    "Contains a special character",
                                    RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(
                                        _passwordController.text)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            child: const Text("Forgot Password?"),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 50, vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                          child: const Text("Login",
                              style: TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _googleSignIn,
                          icon: const FaIcon(FontAwesomeIcons.google,
                              color: Colors.red),
                          label: const Text("Sign in with Google"),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40, vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 700),
                                pageBuilder: (context, animation, secondaryAnimation) =>
                                    RegisterScreen(),
                                transitionsBuilder: (context, animation,
                                    secondaryAnimation, child) {
                                  const begin = Offset(-1.0, 0.0);
                                  const end = Offset.zero;
                                  const curve = Curves.easeInOut;
                                  var tween = Tween(begin: begin, end: end)
                                      .chain(CurveTween(curve: curve));
                                  return SlideTransition(
                                      position: animation.drive(tween),
                                      child: child);
                                },
                              ),
                            );
                          },
                          child: const Text("Don't have an account? Register"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

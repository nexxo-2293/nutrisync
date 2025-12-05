import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutrisync/screens/auth/login_screen.dart';
import 'package:nutrisync/screens/main/main_screen.dart';
import 'package:nutrisync/screens/welcome/welcome_screen.dart';
import '../../services/auth_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../auth/registration_Details.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final AuthService _authService = AuthService();

  int _passwordConditionCount = 0;
  bool _isPasswordValid = false;
  bool _showConfirmPasswordField = false;

  // Email verification state variables
  bool _emailVerificationSent = false;
  bool _isEmailVerified = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      _updatePasswordStrength(_passwordController.text);
      setState(() {}); // update UI when password changes
    });
    _confirmPasswordController.addListener(() {
      setState(() {}); // update UI when confirm password changes
    });
  }

  void _updatePasswordStrength(String password) {
    int conditionsMet = 0;
    // Condition 1: At least 8 characters
    bool conditionLength = password.length >= 8;
    if (conditionLength) conditionsMet++;
    // Condition 2: Contains at least one letter
    bool conditionLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    if (conditionLetter) conditionsMet++;
    // Condition 3: Contains at least one number
    bool conditionNumber = RegExp(r'[0-9]').hasMatch(password);
    if (conditionNumber) conditionsMet++;
    // Condition 4: Contains at least one special character
    bool conditionSpecial =
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    if (conditionSpecial) conditionsMet++;

    setState(() {
      _passwordConditionCount = conditionsMet;
      _isPasswordValid = (conditionsMet == 4);
      _showConfirmPasswordField = _isPasswordValid;
    });
  }

  bool _arePasswordsEnteredAndMatching() {
    return _passwordController.text.isNotEmpty &&
        _confirmPasswordController.text.isNotEmpty &&
        _passwordController.text == _confirmPasswordController.text;
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
        Text(text, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  // Sends the email verification link.
  // If no user exists, creates a new one first.
    void _sendVerificationEmail() async {
      try {
        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          // Try to create the user with the provided email and password.
          User? user = await _authService.register(
            _emailController.text,
            _passwordController.text,
          );
          if (user == null) {
            // Registration failed because the email is already in use.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Email is already in use")),
            );
            return;
          }
          currentUser = user;
        }
        await currentUser.sendEmailVerification();
        setState(() {
          _emailVerificationSent = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Verification email sent. Please check your inbox.")),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Email is already in use")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error sending verification email: ${e.message}")),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error sending verification email: $e")),
        );
      }
    }



  // Checks if the user's email is verified by reloading their profile.
  void _checkEmailVerified() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("No user found. Please send verification email first.")),
        );
        return;
      }
      await currentUser.reload();
      currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser!.emailVerified) {
        setState(() {
          _isEmailVerified = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email verified! You can now register.")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Email not yet verified. Please check your inbox.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error checking verification: $e")),
      );
    }
  }

  // Final registration function.
  // It checks that the email is verified before navigating to the next screen.
  void _register() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please send verification email first.")),
      );
      return;
    }
    await currentUser.reload();
    currentUser = FirebaseAuth.instance.currentUser;
    if (!currentUser!.emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please verify your email before registering.")),
      );
      return;
    }
    // Proceed with registration steps.
    // Since the user is already created and verified, navigate to registration details.
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
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (context, animation, secondaryAnimation) =>
                WelcomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(-1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOut;
              var tween =
                  Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Create an Account",
                            style: theme.textTheme.headlineSmall!
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text("Join NutriSync and get started",
                              style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 30),
                          TextFormField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: "Email",
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (value) =>
                                value == null || value.isEmpty ? "Enter email" : null,
                          ),
                          const SizedBox(height: 15),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: "Password",
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty)
                                return "Enter password";
                              if (!_isPasswordValid)
                                return "Password must be at least 8 characters, contain letters, numbers, and special characters";
                              return null;
                            },
                          ),
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
                                      RegExp(r'[A-Za-z]')
                                          .hasMatch(_passwordController.text)),
                                  _buildPasswordCriteria(
                                      "Contains a number",
                                      RegExp(r'[0-9]')
                                          .hasMatch(_passwordController.text)),
                                  _buildPasswordCriteria(
                                      "Contains a special character",
                                      RegExp(r'[!@#$%^&*(),.?":{}|<>]')
                                          .hasMatch(_passwordController.text)),
                                ],
                              ),
                            ),
                          if (_showConfirmPasswordField)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 15),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: true,
                                  decoration: InputDecoration(
                                    labelText: "Re-enter Password",
                                    filled: true,
                                    fillColor: theme.colorScheme.surface,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return "Re-enter password";
                                    if (value != _passwordController.text)
                                      return "Passwords do not match";
                                    return null;
                                  },
                                ),
                                // Show error immediately if passwords don't match
                                if (_confirmPasswordController.text.isNotEmpty &&
                                    _confirmPasswordController.text !=
                                        _passwordController.text)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      "Passwords do not match",
                                      style:
                                          TextStyle(color: Colors.red, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          // Email Verification UI:
                          // Show "Send Verification Email" only if passwords match
                          if (!_emailVerificationSent &&
                              _arePasswordsEnteredAndMatching())
                            ElevatedButton(
                              onPressed: _sendVerificationEmail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 50, vertical: 15),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30)),
                              ),
                              child: const Text("Send Verification Email",
                                  style: TextStyle(fontSize: 18)),
                            )
                          else if (_emailVerificationSent && !_isEmailVerified)
                            ElevatedButton(
                              onPressed: _checkEmailVerified,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 50, vertical: 15),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30)),
                              ),
                              child: const Text("Check Verification",
                                  style: TextStyle(fontSize: 18)),
                            ),
                          const SizedBox(height: 15),
                          // Registration button - final step.
                          ElevatedButton(
                            onPressed: _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 50, vertical: 15),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                            ),
                            child: const Text("Register",
                                style: TextStyle(fontSize: 18)),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color: theme.colorScheme.onSurfaceVariant)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("OR", style: theme.textTheme.bodyMedium),
                              ),
                              Expanded(
                                  child: Divider(
                                      color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _signInWithGoogle,
                            icon: const FaIcon(FontAwesomeIcons.google,
                                color: Colors.red),
                            label: const Text("Sign Up with Google"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 50, vertical: 15),
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
                                      LoginScreen(),
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
                            child: const Text("Already have an account? Login"),
                          ),
                        ],
                      ),
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

  void _signInWithGoogle() async {
    User? user = await _authService.signInWithGoogle();
    if (user != null) {
      _checkUserDetails(user);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google Sign-In failed")));
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
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }
}

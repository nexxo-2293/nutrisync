import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nutrisync/screens/welcome/welcome_screen.dart';
import 'dart:convert';
import '../../services/auth_service.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  File? _selectedImage;
  String? _analysisResult;
  String? _predictedFood;
  String? _imageUrl;
  double? _confidence;
  bool _isAnalyzing = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  // Cached active server for the session.
  String? _activeServer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _slideAnimation =
        Tween<Offset>(begin: Offset(0, 1), end: Offset(0, 0)).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _analysisResult = null;
        _predictedFood = null;
        _imageUrl = null;
        _confidence = null;
      });
      _animationController.forward(from: 0);
    }
  }

  // New function to quickly check which server is online using parallel checking and caching.
  Future<String?> _getActiveServer() async {
    if (_activeServer != null) return _activeServer;

    // Define your two server upload endpoints.
    const String server1 = 'https://h0qrgv67-5000.inc1.devtunnels.ms/upload';
    const String server2 = 'https://rzfcbm8s-5000.euw.devtunnels.ms/upload';

    // Helper to check a server via its health endpoint.
    Future<bool> isServerOnline(String url) async {
      try {
        final pingUrl = url.replaceAll('/upload', '/ping');
        final response =
            await http.get(Uri.parse(pingUrl)).timeout(Duration(milliseconds: 2500));
        print("Ping response from $pingUrl: '${response.body}'");
        return response.statusCode == 200 &&
            response.body.toLowerCase().contains("pong");
      } catch (e) {
        print("Error checking server at $url: $e");
        return false;
      }
    }

    // Check both servers in parallel.
    final results = await Future.wait([isServerOnline(server1), isServerOnline(server2),]);
    if (results[0] == true && results[1] == true) {
      _activeServer = server1; // choose server1 if both are online
    } else if (results[0] == true) {
      _activeServer = server1;
    } else if (results[1] == true) {
      _activeServer = server2;
    } else {
      _activeServer = null; // All servers are offline
    }
    return _activeServer;
  }

  // Helper function to retrieve user details from Firestore.
  Future<Map<String, String>> _getUserDetails() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!userDoc.exists) return {};
    Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

    // Debug print to verify Firestore data.
    print("Firestore user data: $data");

    return {
      'age': data['age']?.toString() ?? '',
      'weight': data['weight']?.toString() ?? '',
      'activityLevel': data['activityLevel']?.toString() ?? '',
      // Convert healthConditions (which may be a list) to a string.
      'healthConditions': data['healthConditions'] != null
          ? data['healthConditions'].toString()
          : '',
      // If your registration uses a different key (e.g., 'notes'), adjust accordingly.
      'notes': data['notes']?.toString() ?? '',
    };
  }

  // Modified _analyzeImage() to include user details.
  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
    });

    // Check which server is online quickly.
    final activeServer = await _getActiveServer();
    if (activeServer == null) {
      setState(() {
        _analysisResult =
            "Failed to analyze image: All servers are offline. Please try again later.";
        _isAnalyzing = false;
      });
      return;
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse(activeServer));

      // Retrieve and add user details to the request fields.
      Map<String, String> userDetails = await _getUserDetails();
      print("Sending user details: $userDetails");
      request.fields.addAll(userDetails);

      request.files.add(
        await http.MultipartFile.fromPath('image', _selectedImage!.path),
      );

      // Set a short timeout so that if the server hangs, the user is updated quickly.
      var response =
          await request.send().timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var decodedResponse = json.decode(responseData);
        setState(() {
          _predictedFood = decodedResponse['predicted_food'] ?? "Unknown";
          _analysisResult =
              decodedResponse['nutritional_info'] ?? "No response received";
          _imageUrl = decodedResponse['image_url'] ?? "";
          _confidence = decodedResponse['confidence'] != null
              ? decodedResponse['confidence'].toDouble()
              : null;
          _isAnalyzing = false;
        });

        storeAnalysisResult(
            _predictedFood!, _imageUrl!, _confidence ?? 0.0, _analysisResult!,
            DateTime.now().toIso8601String());
      } else {
        setState(() {
          _analysisResult =
              "Failed to analyze image: The server is currently OFF please try again later";
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      setState(() {
        _analysisResult = "An error occurred";
        _isAnalyzing = false;
      });
    }
  }

  void _resetHomeScreen() {
    setState(() {
      _selectedImage = null;
      _analysisResult = null;
      _predictedFood = null;
      _imageUrl = null;
      _confidence = null;
    });
  }

  void _logout(BuildContext context) {
    _authService.logout();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => WelcomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withAlpha(51),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Analyze Your Food",
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "for Nutritional Information",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onPrimary.withAlpha(230),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictedFoodWidget() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "Predicted Food: ${_predictedFood ?? "Unknown"}",
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildUploadAnotherButton() {
    final theme = Theme.of(context);
    return TextButton.icon(
      icon: Icon(Icons.camera_alt, color: theme.colorScheme.primary),
      label: Text(
        'Upload Another',
        style: GoogleFonts.poppins(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: () => _pickImage(ImageSource.gallery),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(Icons.fastfood,
              color: theme.colorScheme.onPrimary, size: 28),
        ),
        title: Text(
          "NutriSync",
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: theme.colorScheme.onPrimary),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              _buildHeader(context),
              SizedBox(height: 24),
              AnimatedSwitcher(
                duration: Duration(milliseconds: 500),
                child: _selectedImage != null
                    ? _buildImagePreview()
                    : _buildPlaceholder(),
              ),
              SizedBox(height: 40),
              if (_selectedImage == null) _buildUploadButtons(),
              if (_selectedImage != null && _analysisResult == null)
                Column(
                  children: [
                    _buildAnalyzeButton(),
                    SizedBox(height: 20),
                    _buildUploadAnotherButton(),
                  ],
                ),
              if (_analysisResult != null)
                SlideTransition(
                  position: _slideAnimation,
                  child: _buildResultCard(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Hero(
      tag: 'food-image',
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withAlpha(51),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.file(_selectedImage!, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    final theme = Theme.of(context);
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withAlpha(26),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fastfood,
            size: 60,
            color: theme.iconTheme.color?.withAlpha(153),
          ),
          SizedBox(height: 12),
          Text(
            "No Image Selected",
            style: GoogleFonts.poppins(
              color: theme.hintColor,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 12),
          Icon(
            Icons.camera_alt,
            size: 30,
            color: theme.iconTheme.color?.withAlpha(153),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButtons() {
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      alignment: WrapAlignment.center,
      children: [
        _ActionButton(
          icon: Icons.photo_library,
          label: "Gallery",
          color: Theme.of(context).colorScheme.primary,
          onPressed: () => _pickImage(ImageSource.gallery),
        ),
        _ActionButton(
          icon: Icons.camera_alt,
          label: "Camera",
          color: Theme.of(context).colorScheme.secondary,
          onPressed: () => _pickImage(ImageSource.camera),
        ),
      ],
    );
  }

  Widget _buildAnalyzeButton() {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: _isAnalyzing ? 80 : 220,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withAlpha(77),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: _isAnalyzing ? null : _analyzeImage,
          child: Center(
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: _isAnalyzing
                  ? SpinKitWave(color: theme.colorScheme.onPrimary, size: 30)
                  : Text(
                      "Analyze Now",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withAlpha(51),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPredictedFoodWidget(),
            SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.restaurant_menu, color: theme.colorScheme.primary),
                SizedBox(width: 10),
                Text(
                  "Analysis Result",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Container(
              height: (_analysisResult!.length > 100) ? 500 : 200,
              child: SingleChildScrollView(
                child: Text(
                  _analysisResult!,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    height: 1.5,
                    color: theme.textTheme.bodyLarge?.color?.withAlpha(230),
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            Center(
              child: _ActionButton(
                icon: Icons.refresh,
                label: "New Scan",
                color: theme.colorScheme.secondary,
                onPressed: _resetHomeScreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: color,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withAlpha(51),
              offset: Offset(4, 4),
              blurRadius: 10,
            ),
            BoxShadow(
              color: theme.highlightColor.withAlpha(179),
              offset: Offset(-4, -4),
              blurRadius: 10,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: theme.colorScheme.onPrimary),
                  SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void storeAnalysisResult(String foodName, String imageUrl, double confidence,
    String analysisResult, String timestamp) async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('history')
      .add({
    'predictedFood': foodName,
    'image_url': imageUrl,
    'confidence': confidence,
    'nutritional_info': analysisResult,
    'timestamp': Timestamp.fromDate(DateTime.parse(timestamp)),
  });
}

// New function to send user details stored during registration to your backend API.
Future<void> sendUserDetails() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Fetch user details from Firestore.
  DocumentSnapshot userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();
  if (!userDoc.exists) return;
  Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

  // Optionally add details from FirebaseAuth.
  userData['uid'] = user.uid;
  userData['email'] = user.email;

  // Include additional registration details.
  userData['age'] = userData['age'] ?? '';
  userData['weight'] = userData['weight'] ?? '';
  userData['activityLevel'] = userData['activityLevel'] ?? '';
  userData['healthConditions'] = userData['healthConditions'] ?? '';
  userData['notes'] = userData['notes'] ?? '';

  // List of backend servers
  List<String> backendApiUrls = [
    'https://h0qrgv67-5000.inc1.devtunnels.ms/upload',
    'https://rzfcbm8s-5000.euw.devtunnels.ms/upload',
    
  ];

  for (String url in backendApiUrls) {
    try {
      var response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(userData),
          )
          .timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        print("User details sent successfully to $url");
        return; // Stop trying other URLs if one succeeds
      } else {
        print("Failed to send user details to $url. Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error sending user details to $url: $e");
    }
  }

  print("All server attempts failed.");
}

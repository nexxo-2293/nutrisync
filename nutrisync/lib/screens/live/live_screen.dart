import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img; // Use the image package for image manipulation
import 'package:path_provider/path_provider.dart';

class LiveFoodScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  LiveFoodScreen({required this.cameras});

  @override
  _LiveFoodScreenState createState() => _LiveFoodScreenState();
}

class _LiveFoodScreenState extends State<LiveFoodScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isStreaming = false;
  List<dynamic> _predictions = [];
  int _selectedCameraIdx = 0;
  Timer? _frameTimer;
  bool _isProcessing = false; // Avoid overlapping frame processing

  // For upload result
  String _uploadResult = "";
  bool _showUploadResult = false;

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  // Cached active server URLs for the session.
  String? _activePredictServer;
  String? _activeUploadServer;

  @override
  void initState() {
    super.initState();
    // Initialize UI animations similar to HomeScreen.
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 1),
      end: Offset(0, 0),
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    // Camera initialization will start when user taps "Start"
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _cameraController?.dispose();
    _animationController.dispose();
    super.dispose();
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
 
  /// Get active server URL based on type ('upload' or 'predict') using parallel checking.
  Future<String?> _getActiveServer(String type) async {
    // Return the cached server if already determined.
    if (type == 'predict' && _activePredictServer != null) {
      return _activePredictServer;
    }
    if (type == 'upload' && _activeUploadServer != null) {
      return _activeUploadServer;
    }

    // Determine the endpoint based on the type.
    String endpoint = type == 'upload' ? 'upload' : 'predict';
    String server1 = type == 'upload'
        ? 'https://h0qrgv67-5000.inc1.devtunnels.ms/upload'
        : 'https://h0qrgv67-5000.inc1.devtunnels.ms/predict';
    String server2 = type == 'upload'
        ? 'https://rzfcbm8s-5000.euw.devtunnels.ms/upload'
        : 'https://rzfcbm8s-5000.euw.devtunnels.ms/predict';
    

    Future<bool> isServerOnline(String url) async {
      try {
        // Use a /ping endpoint by replacing the current endpoint with /ping.
        final pingUrl = url.replaceAll('/$endpoint', '/ping');
        final response =
            await http.get(Uri.parse(pingUrl)).timeout(Duration(seconds: 3));
        print("Ping response from $pingUrl: '${response.body}'");
        return response.statusCode == 200 &&
            response.body.toLowerCase().contains("pong");
      } catch (e) {
        print("Error checking server at $url: $e");
        return false;
      }
    }

    // Run both server checks in parallel.
    final results = await Future.wait([isServerOnline(server1), isServerOnline(server2)]);
    
    String? chosenServer;
    if (results[0] == true && results[1] == true) {
      // If both servers are online, choose the one that responded first.
      // Here, we simply choose server1.
      chosenServer = server1;
    } else if (results[0] == true) {
      chosenServer = server1;
    } else if (results[1] == true) {
      chosenServer = server2;
    } else {
      // If all servers are offline, return null.
      print("All servers are offline.");
      chosenServer = null;
    }

    // Cache the chosen server for the session.
    if (type == 'predict') {
      _activePredictServer = chosenServer;
    } else {
      _activeUploadServer = chosenServer;
    }
    return chosenServer;
  }

  /// Initialize the camera with the selected index.
  Future<void> _initializeCamera() async {
    // Added web check: if running on Web, print warning and return.
    if (kIsWeb) {
      print("⚠️ Camera is not supported on Web!");
      return;
    }
    if (widget.cameras.isEmpty) return;
    _cameraController = CameraController(
      widget.cameras[_selectedCameraIdx],
      ResolutionPreset.high, // Use high resolution to avoid compression
      enableAudio: false,
    );
    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
      _startStreaming();
    } catch (e) {
      print("Error initializing camera: $e");
    }
  }

  /// Start capturing frames periodically.
  void _startStreaming() {
    _isStreaming = true;
    _frameTimer = Timer.periodic(Duration(seconds: 2), (_) {
      _captureFrameAndSend();
    });
  }

  /// Stop capturing frames.
  void _stopStreaming() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _isStreaming = false;
  }

  /// Capture a frame and send it to the backend for predictions.
  Future<void> _captureFrameAndSend() async {
    if (!_isCameraInitialized ||
        _cameraController == null ||
        !_isStreaming ||
        _isProcessing) return;
    _isProcessing = true;
    try {
      XFile file = await _cameraController!.takePicture();
      File imageFile = File(file.path);
      List<int> imageBytes = await imageFile.readAsBytes();
      print("Captured image: ${file.path}");
      print("Image byte size: ${imageBytes.length}");
      
      // Remove rotation: use the image bytes as captured.
      Uint8List imageUint8List = Uint8List.fromList(imageBytes);
      
      // Convert to base64 string directly.
      String base64Image = base64Encode(imageUint8List);
      
      var payload = jsonEncode({
        'image': 'data:image/jpeg;base64,$base64Image',
      });
      
      // Use the active server for predictions.
      String? activePredictServer = await _getActiveServer('predict');
      if (activePredictServer == null) {
        setState(() {
          _predictions = [];
        });
        _isProcessing = false;
        return;
      }
      Uri url = Uri.parse(activePredictServer);
      
      http.Response response = await http
          .post(url,
              headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        var result = jsonDecode(response.body);
        setState(() {
          _predictions = result['predictions'] ?? [];
        });
      } else {
        setState(() {
          _predictions = [];
        });
      }
    } catch (e) {
      setState(() {
        _predictions = [];
      });
      print("Error in _captureFrameAndSend: $e");
    } finally {
      _isProcessing = false;
    }
  }

  /// Immediately capture a frame and call the upload function using the selected prediction.
  Future<void> _uploadSelectedPrediction(String predictedFood) async {
    if (!_isCameraInitialized || _cameraController == null) return;
    print("Uploading for prediction: $predictedFood");

    // Stop the streaming immediately.
    _stopStreaming();
    
    // Wait a bit to ensure that any pending capture is complete.
    await Future.delayed(Duration(milliseconds: 300));
    
    // Ensure that the camera is not busy with a capture.
    while (_cameraController!.value.isTakingPicture) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    // Clear predictions so the UI state is reset.
    setState(() {
      _predictions = [];
    });
    
    try {
      // Capture the final frame for upload.
      XFile file = await _cameraController!.takePicture();
      File imageFile = File(file.path);
      print("Captured image for upload: ${file.path}");

      List<int> imageBytes = await imageFile.readAsBytes();
      Uint8List imageUint8List = Uint8List.fromList(imageBytes);
      
      // Save the captured image to a temporary file.
      final tempDir = await getTemporaryDirectory();
      File savedFile = File('${tempDir.path}/captured.jpg');
      await savedFile.writeAsBytes(imageUint8List);
      
      // Call the upload function with the captured image.
      await _uploadFileWithPrediction(predictedFood, savedFile);
    } catch (e) {
      print("Error capturing frame for upload: $e");
    }
  }


  Future<Map<String, String>> _getUserDetails() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!userDoc.exists) return {};
    Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
    return {
      'age': data['age']?.toString() ?? '',
      'weight': data['weight']?.toString() ?? '',
      'activityLevel': data['activityLevel']?.toString() ?? '',
      'healthConditions': data['healthConditions'] != null
          ? data['healthConditions'].toString()
          : '',
      'notes': data['notes']?.toString() ?? '',
    };
  }

  Future<void> _uploadFileWithPrediction(String predictedFood, File imageFile) async {
    try {
      // Use the active server for upload.
      String? activeUploadServer = await _getActiveServer('upload');
      if (activeUploadServer == null) {
        print("All servers are offline. Cannot upload.");
        setState(() {
          _uploadResult = "Failed to upload: All servers are offline.";
          _showUploadResult = true;
        });
        return;
      }
      var uri = Uri.parse(activeUploadServer);
      var request = http.MultipartRequest('POST', uri);

      request.fields['predicted_food'] = predictedFood;

      Map<String, String> userDetails = await _getUserDetails();
      request.fields.addAll(userDetails);

      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      var response = await request.send().timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        var responseBody = await response.stream.bytesToString();
        print("Upload successful: $responseBody");
        setState(() {
          _uploadResult = responseBody;
          _showUploadResult = true;
        });
        // Parse the response.
        var decodedResponse = jsonDecode(responseBody);
        String foodName = decodedResponse['predicted_food'] ?? predictedFood;
        String imageUrl = decodedResponse['image_url'] ?? "";
        double confidence = decodedResponse['confidence'] != null
            ? decodedResponse['confidence'].toDouble()
            : 0.0;
        String analysisResult = decodedResponse['nutritional_info'] ?? "";
        
        try {
          storeAnalysisResult(foodName, imageUrl, confidence, analysisResult,
              DateTime.now().toIso8601String());
        } catch (e) {
          print("Error storing analysis result: $e");
        }
      } else {
        print("Upload failed with status: ${response.statusCode}");
        setState(() {
          _uploadResult = "Upload failed with status: ${response.statusCode}";
          _showUploadResult = true;
        });
      }
    } catch (e) {
      print("Error during upload: $e");
      setState(() {
        _uploadResult = "Error during upload: $e";
        _showUploadResult = true;
        _activeUploadServer = null;
        _activePredictServer = null;
      });
    }
  }

  /// Switch between available cameras.
  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    _selectedCameraIdx = (_selectedCameraIdx + 1) % widget.cameras.length;
    await _cameraController?.dispose();
    setState(() {
      _isCameraInitialized = false;
    });
    await _initializeCamera();
  }

  /// Build a gradient header similar to HomeScreen.
  Widget _buildHeader() {
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Live Food Detection",
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Get real-time nutritional info",
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

  /// Build the camera preview maintaining the original aspect ratio.
  Widget _buildCameraPreview() {
    if (!_isCameraInitialized || _cameraController == null) {
      return Center(child: CircularProgressIndicator());
    }
    return Container(
      color: Colors.black, // Fallback background
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize!.height,
          height: _cameraController!.value.previewSize!.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  /// Build the control buttons including Switch and Start/Stop.
  Widget _buildControlButtons() {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Switch Camera button.
        GestureDetector(
          onTap: _switchCamera,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: theme.colorScheme.secondary,
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
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.switch_camera,
                  color: theme.colorScheme.onPrimary,
                ),
                SizedBox(width: 12),
                Text(
                  "Switch",
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
        SizedBox(width: 20),
        // Start/Stop button.
        GestureDetector(
          onTap: () async {
            if (_isStreaming) {
              _stopStreaming();
            } else {
              await _initializeCamera();
            }
            setState(() {});
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: theme.colorScheme.secondary,
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
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isStreaming ? Icons.stop : Icons.play_arrow,
                  color: theme.colorScheme.onPrimary,
                ),
                SizedBox(width: 12),
                Text(
                  _isStreaming ? "Stop" : "Start",
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
      ],
    );
  }

  /// Build a single prediction overlay (only the top prediction).
  Widget _buildPredictionResult() {
    if (_predictions.isEmpty || _showUploadResult) return SizedBox.shrink();
    final theme = Theme.of(context);
    // Use only the first prediction.
    final prediction = _predictions.first;
    final String label = prediction['predicted_class'];
    final double confidence = prediction['confidence'];
  
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: GestureDetector(
        onTap: () async {
          // Clear predictions to freeze the selected one.
          setState(() {
            _predictions = [];
          });
          print("Tapped prediction: $label");
          await _uploadSelectedPrediction(label);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withAlpha(127), // Transparent overlay with no solid background
          ),
          child: Text(
            "$label ${(confidence * 100).toStringAsFixed(0)}%",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// Build an upload result widget that displays upload function response.
  Widget _buildUploadResult() {
    if (!_showUploadResult) return SizedBox.shrink();
    final theme = Theme.of(context);

    // Attempt to parse _uploadResult as JSON
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(_uploadResult);
    } catch (e) {
      decoded = null;
    }

    // Extract fields if JSON parsing succeeded
    String predictedFood = decoded?['predicted_food'] ?? "Unknown";
    double confidence = decoded?['confidence']?.toDouble() ?? 0.0;
    String nutritionalInfo = decoded?['nutritional_info'] ?? _uploadResult;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardColor.withAlpha(230), // Slightly transparent
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
          mainAxisSize: MainAxisSize.min, // Allow flexible height
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gradient header for predicted food
            Container(
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
                "Predicted Food: $predictedFood",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 20),
            // Analysis Result Title
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
            // Nutritional info (now fully dynamic)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  nutritionalInfo,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    height: 1.5,
                    color: theme.textTheme.bodyLarge?.color?.withAlpha(230),
                  ),
                ),
              ),
            ),
            // Close or "New Scan" button
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _uploadResult = "";
                    _showUploadResult = false;
                  });
                },
                child: Container(
                  margin: EdgeInsets.only(top: 20),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Text(
                    "New Scan",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimary,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            Icons.fastfood,
            color: theme.colorScheme.onPrimary,
            size: 28,
          ),
        ),
        title: Text(
          "Live Food",
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack( // Use Stack for layering
        children: [
          // Full-screen camera preview
          Positioned.fill(
            child: _buildCameraPreview(),
          ),

          // Transparent single prediction overlay at the top (only the top prediction)
          if (_predictions.isNotEmpty && _isStreaming)
            Positioned(
              top: 24,
              left: 24,
              right: 24,
              child: GestureDetector(
                onTap: () async {
                  final String label = _predictions.first['predicted_class'];
                  print("Tapped prediction: $label");
                  await _uploadSelectedPrediction(label);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withAlpha(127), // Transparent overlay
                  ),
                  child: Text(
                    "${_predictions.first['predicted_class']} ${(_predictions.first['confidence'] * 100).toStringAsFixed(0)}%",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          // Control buttons overlay
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _buildControlButtons(),
            ),
          ),

          // Upload result overlay
          if (_showUploadResult)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildUploadResult(),
            ),
        ],
      ),
    );
  }
}

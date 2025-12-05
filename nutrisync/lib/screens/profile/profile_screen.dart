import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../welcome/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  User? _user;

  // Basic info
  String? _name;
  String? _email;
  String? _profilePicUrl;

  // Health Conditions (existing)
  String? _healthConditions;
  List<String> _healthConditionsList = [];

  // Registration Details (new fields from registration_details)
  int? _age;
  String? _gender;
  double? _weight;
  double? _height;
  String? _activityLevel;
  String? _notes;

  // Options for dropdowns
  final List<String> _genders = ["Male", "Female", "Other"];
  final List<String> _activityLevels = [
    "Sedentary",
    "Lightly Active",
    "Moderately Active",
    "Very Active"
  ];

  // Firestore listener for auto refresh
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _loadLocalData(); // Load cached details on startup
    _loadUserData();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  // Save basic user data to local device
  Future<void> _saveLocalData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_name != null) prefs.setString('name', _name!);
    if (_email != null) prefs.setString('email', _email!);
    if (_profilePicUrl != null) prefs.setString('profilePicUrl', _profilePicUrl!);
    if (_healthConditionsList.isNotEmpty) {
      prefs.setStringList('healthConditions', _healthConditionsList);
    } else {
      prefs.remove('healthConditions');
    }
    // You can also cache additional registration details if desired.
  }

  // Load user data from local device
  Future<void> _loadLocalData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('name') ?? _name;
      _email = prefs.getString('email') ?? _email;
      _profilePicUrl = prefs.getString('profilePicUrl') ?? _profilePicUrl;
      _healthConditionsList =
          prefs.getStringList('healthConditions') ?? _healthConditionsList;
      _healthConditions = _healthConditionsList.isNotEmpty
          ? _healthConditionsList.join(', ')
          : "Not specified";
    });
  }

  // Clear user data from local storage when logging out
  Future<void> _clearLocalData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('name');
    await prefs.remove('email');
    await prefs.remove('profilePicUrl');
    await prefs.remove('healthConditions');
  }

  // Fetch user data from Firestore and set up auto refresh
  Future<void> _loadUserData() async {
    _user = _auth.currentUser;
    if (_user != null) {
      setState(() {
        _email = _user!.email;
        _name = _user!.displayName ?? "Unknown";
        _profilePicUrl = _user!.photoURL;
      });

      // Listen for document changes for auto refresh
      _userSubscription = _firestore
          .collection('users')
          .doc(_user!.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          Map<String, dynamic> data =
              snapshot.data() as Map<String, dynamic>;
          setState(() {
            _name = data['name'] ?? _user!.displayName ?? "Unknown";
            _profilePicUrl = data['profilePic'] ?? _profilePicUrl;
            // Health conditions
            if (data.containsKey('healthConditions') &&
                data['healthConditions'] is List) {
              _healthConditionsList =
                  List<String>.from(data['healthConditions']);
              _healthConditions = _healthConditionsList.isNotEmpty
                  ? _healthConditionsList.join(', ')
                  : "Not specified";
            } else {
              _healthConditions = "Not specified";
            }
            // Registration details
            _age = data['age'];
            _gender = data['gender'];
            _weight = data['weight'] != null
                ? (data['weight'] as num).toDouble()
                : null;
            _height = data['height'] != null
                ? (data['height'] as num).toDouble()
                : null;
            _activityLevel = data['activityLevel'];
            _notes = data['notes'];
          });
          _saveLocalData();
        }
      });
    }
  }

  // Pull-to-refresh function (in addition to auto refresh)
  Future<void> _reloadData() async {
    await _loadUserData();
  }

  // Allow all users (including Google) to change their profile picture.
  Future<void> _uploadProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      File file = File(image.path);
      try {
        TaskSnapshot snapshot = await FirebaseStorage.instance
            .ref('profile_pictures/${_user!.uid}.jpg')
            .putFile(file);
        String downloadUrl = await snapshot.ref.getDownloadURL();

        await _firestore
            .collection('users')
            .doc(_user!.uid)
            .update({'profilePic': downloadUrl});

        setState(() {
          _profilePicUrl = downloadUrl;
        });
      } catch (e) {
        print("Error uploading image: $e");
      }
    }
  }

  // Edit health conditions with add/remove functionality
  void _editHealthConditions() {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text("Edit Health Conditions"),
            content: SingleChildScrollView(
              child: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: "Add Health Condition",
                        suffixIcon: IconButton(
                          icon: Icon(Icons.add),
                          onPressed: () {
                            if (controller.text.trim().isNotEmpty) {
                              setStateDialog(() {
                                _healthConditionsList.add(controller.text.trim());
                              });
                              controller.clear();
                            }
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Container(
                      height: 150,
                      child: ListView.builder(
                        itemCount: _healthConditionsList.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(_healthConditionsList[index]),
                            trailing: IconButton(
                              icon: Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () {
                                setStateDialog(() {
                                  _healthConditionsList.removeAt(index);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel")),
              TextButton(
                onPressed: () async {
                  await _firestore
                      .collection('users')
                      .doc(_user!.uid)
                      .update({'healthConditions': _healthConditionsList});
                  setState(() {
                    _healthConditions = _healthConditionsList.isNotEmpty
                        ? _healthConditionsList.join(', ')
                        : "Not specified";
                  });
                  Navigator.pop(context);
                },
                child: Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  // Edit user name with an updated UI
  void _editUserName() {
    TextEditingController controller = TextEditingController(text: _name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit Name"),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel")),
          TextButton(
            onPressed: () async {
              await _firestore
                  .collection('users')
                  .doc(_user!.uid)
                  .update({'name': controller.text.trim()});
              setState(() {
                _name = controller.text.trim();
              });
              Navigator.pop(context);
            },
            child: Text("Save"),
          ),
        ],
      ),
    );
  }

  // New: Edit Registration Details dialog
  void _editRegistrationDetails() {
    // Controllers for numeric and text fields
    TextEditingController ageController =
        TextEditingController(text: _age?.toString() ?? "");
    TextEditingController weightController =
        TextEditingController(text: _weight?.toString() ?? "");
    TextEditingController heightController =
        TextEditingController(text: _height?.toString() ?? "");
    TextEditingController notesController =
        TextEditingController(text: _notes ?? "");

    // Local dropdown selections
    String? selectedGender = _gender;
    String? selectedActivityLevel = _activityLevel;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Edit Registration Details"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                // Age
                TextField(
                  controller: ageController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Age",
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                // Gender Dropdown
                DropdownButtonFormField<String>(
                  value: selectedGender,
                  hint: Text("Select Gender"),
                  items: _genders
                      .map((gender) => DropdownMenuItem(
                            value: gender,
                            child: Text(gender),
                          ))
                      .toList(),
                  onChanged: (value) {
                    selectedGender = value;
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                // Weight
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Weight (kg)",
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                // Height
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Height (cm)",
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                // Activity Level Dropdown
                DropdownButtonFormField<String>(
                  value: selectedActivityLevel,
                  hint: Text("Select Activity Level"),
                  items: _activityLevels
                      .map((level) => DropdownMenuItem(
                            value: level,
                            child: Text(level),
                          ))
                      .toList(),
                  onChanged: (value) {
                    selectedActivityLevel = value;
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                // Additional Notes
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Additional Notes",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel")),
            TextButton(
              onPressed: () async {
                // Parse values safely
                int? newAge = int.tryParse(ageController.text.trim());
                double? newWeight =
                    double.tryParse(weightController.text.trim());
                double? newHeight =
                    double.tryParse(heightController.text.trim());

                await _firestore.collection('users').doc(_user!.uid).update({
                  'age': newAge ?? _age,
                  'gender': selectedGender ?? _gender,
                  'weight': newWeight ?? _weight,
                  'height': newHeight ?? _height,
                  'activityLevel': selectedActivityLevel ?? _activityLevel,
                  'notes': notesController.text.trim(),
                });
                Navigator.pop(context);
              },
              child: Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // Logout function with local cache clearing
  void _logout(BuildContext context) async {
    await _clearLocalData();
    await _authService.logout();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => WelcomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
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
          child: Icon(Icons.person,
              color: theme.colorScheme.onPrimary, size: 28),
        ),
        title: Text("Profile",
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimary,
            )),
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
      body: _user == null
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reloadData,
              child: SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Profile picture with edit overlay using a Stack
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: _profilePicUrl != null
                                ? NetworkImage(_profilePicUrl!)
                                : null,
                            child: _profilePicUrl == null
                                ? Icon(Icons.person, size: 50)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _uploadProfilePicture,
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.primary,
                                ),
                                child: Icon(Icons.camera_alt,
                                    size: 18,
                                    color: theme.colorScheme.onPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      // Name with edit option
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_name ?? "Unknown",
                              style: theme.textTheme.titleLarge),
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: _editUserName,
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.edit,
                                  size: 18,
                                  color: theme.colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(_email ?? "No email",
                          style: theme.textTheme.bodyMedium),
                      SizedBox(height: 20),
                      // Health Conditions section
                      ListTile(
                        title: Text("Health Conditions",
                            style: theme.textTheme.titleMedium),
                        subtitle: Text(_healthConditions ?? "Not specified"),
                        trailing: GestureDetector(
                          onTap: _editHealthConditions,
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.edit,
                                size: 18, color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      // New Registration Details section
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: ExpansionTile(
                          title: Text("Registration Details",
                              style: theme.textTheme.titleMedium),
                          children: [
                            ListTile(
                              title: Text("Age"),
                              subtitle: Text(
                                  _age != null ? _age.toString() : "Not specified"),
                            ),
                            ListTile(
                              title: Text("Gender"),
                              subtitle: Text(_gender ?? "Not specified"),
                            ),
                            ListTile(
                              title: Text("Weight (kg)"),
                              subtitle: Text(_weight != null
                                  ? _weight.toString()
                                  : "Not specified"),
                            ),
                            ListTile(
                              title: Text("Height (cm)"),
                              subtitle: Text(_height != null
                                  ? _height.toString()
                                  : "Not specified"),
                            ),
                            ListTile(
                              title: Text("Activity Level"),
                              subtitle:
                                  Text(_activityLevel ?? "Not specified"),
                            ),
                            ListTile(
                              title: Text("Additional Notes"),
                              subtitle: Text(_notes ?? "Not specified"),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _editRegistrationDetails,
                                child: Text("Edit Details"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

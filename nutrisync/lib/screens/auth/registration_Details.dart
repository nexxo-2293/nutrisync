import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main/main_screen.dart';

class RegistrationDetailsScreen extends StatefulWidget {
  @override
  _RegistrationDetailsScreenState createState() =>
      _RegistrationDetailsScreenState();
}

class _RegistrationDetailsScreenState extends State<RegistrationDetailsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for existing fields.
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  List<TextEditingController> _healthConditionControllers = [];

  // New controllers for additional fields.
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Dropdown values.
  String? _selectedGender;
  String? _selectedActivityLevel;
  final List<String> _genders = ["Male", "Female", "Other"];
  final List<String> _activityLevels = [
    "Sedentary",
    "Lightly Active",
    "Moderately Active",
    "Very Active"
  ];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Track if the user is logged in with Google.
  bool _isGoogleUser = false;

  @override
  void initState() {
    super.initState();
    // Start with one health condition field.
    _healthConditionControllers.add(TextEditingController());
    User? user = _auth.currentUser;
    if (user != null) {
      _isGoogleUser = user.providerData
          .any((provider) => provider.providerId == "google.com");
      if (_isGoogleUser && user.displayName != null) {
        _nameController.text = user.displayName!;
      }
    }
  }

  void _addHealthConditionField() {
    setState(() {
      _healthConditionControllers.add(TextEditingController());
    });
  }

  void _removeHealthConditionField(int index) {
    if (_healthConditionControllers.length > 1) {
      setState(() {
        _healthConditionControllers[index].dispose();
        _healthConditionControllers.removeAt(index);
      });
    }
  }

  Future<void> _saveDetails() async {
    User? user = _auth.currentUser;
    if (user != null) {
      // Gather non-empty health conditions.
      List<String> healthConditions = _healthConditionControllers
          .map((controller) => controller.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      await _firestore.collection('users').doc(user.uid).set({
        'name': _nameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'gender': _selectedGender ?? "",
        'weight': double.tryParse(_weightController.text.trim()) ?? 0,
        'height': double.tryParse(_heightController.text.trim()) ?? 0,
        'activityLevel': _selectedActivityLevel ?? "",
        'healthConditions': healthConditions,
        'notes': _notesController.text.trim(),
      }, SetOptions(merge: true));

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: Duration(milliseconds: 800),
          pageBuilder: (context, animation, secondaryAnimation) =>
              MainScreen(),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
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

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _notesController.dispose();
    for (var controller in _healthConditionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Registration Details"),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Field (read-only for Google users)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _nameController,
                      readOnly: _isGoogleUser,
                      decoration: InputDecoration(
                        labelText: "Name",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Age Field
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _ageController,
                      decoration: InputDecoration(
                        labelText: "Age",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Gender Dropdown
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: DropdownButtonFormField<String>(
                      value: _selectedGender,
                      hint: Text("Select Gender"),
                      items: _genders
                          .map((gender) => DropdownMenuItem(
                                value: gender,
                                child: Text(gender),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedGender = value;
                        });
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please select a gender";
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Weight Field
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _weightController,
                      decoration: InputDecoration(
                        labelText: "Weight (kg)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Height Field
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _heightController,
                      decoration: InputDecoration(
                        labelText: "Height (cm)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Activity Level Dropdown
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: DropdownButtonFormField<String>(
                      value: _selectedActivityLevel,
                      hint: Text("Select Activity Level"),
                      items: _activityLevels
                          .map((level) => DropdownMenuItem(
                                value: level,
                                child: Text(level),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedActivityLevel = value;
                        });
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please select an activity level";
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Health Conditions Section
                Text("Health Conditions",
                    style: theme.textTheme.titleMedium),
                SizedBox(height: 5),
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: _healthConditionControllers.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _healthConditionControllers[index],
                              decoration: InputDecoration(
                                hintText: "Enter health condition",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          // Show add icon only for the last field.
                          if (index == _healthConditionControllers.length - 1)
                            IconButton(
                              icon: Icon(Icons.add,
                                  color: theme.colorScheme.primary),
                              onPressed: _addHealthConditionField,
                            ),
                          // Show remove icon if there’s more than one field.
                          if (_healthConditionControllers.length > 1)
                            IconButton(
                              icon: Icon(Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: () =>
                                  _removeHealthConditionField(index),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                SizedBox(height: 10),
                // Additional Notes Field
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: "Additional Notes",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                // Save Details Button
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      await _saveDetails();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    surfaceTintColor: theme.colorScheme.onSurface,
                    foregroundColor: theme.colorScheme.secondary,
                    minimumSize: Size(double.infinity, 50),
                  ),
                  child: Text("Save Details"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

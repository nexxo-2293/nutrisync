import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Save user details after signup
  Future<void> saveUserData(String email, int age, List<String> healthConditions) async {
    String uid = _auth.currentUser!.uid;
    await _db.collection("users").doc(uid).set({
      "email": email,
      "age": age,
      "healthConditions": healthConditions,
      "createdAt": Timestamp.now(),
    });
  }

  // Fetch user data
  Future<Map<String, dynamic>?> getUserData() async {
    String uid = _auth.currentUser!.uid;
    DocumentSnapshot doc = await _db.collection("users").doc(uid).get();
    if (doc.exists) {
      return doc.data() as Map<String, dynamic>;
    }
    return null;
  }
}

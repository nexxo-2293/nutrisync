import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _selectedDate;

  /// Fetch the history data from Firestore for the current user.
  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .get();

      // Convert each document into a Map<String, dynamic>.
      return snapshot.docs.map((doc) {
        return doc.data() as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      print("Error fetching history: $e");
      return [];
    }
  }

  /// Pull-to-refresh triggers this to rebuild and re-fetch data.
  Future<void> _reloadHistory() async {
    setState(() {}); // Causes the FutureBuilder to run again
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(Icons.history, color: theme.colorScheme.onPrimary, size: 28),
        ),
        title: Text(
          "History",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'pick_date') {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate != null
                      ? DateTime.parse(_selectedDate!)
                      : DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (pickedDate != null) {
                  setState(() {
                    _selectedDate = DateFormat('yyyy-MM-dd').format(pickedDate);
                  });
                }
              } else if (value == 'reset') {
                setState(() {
                  _selectedDate = null;
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'pick_date',
                child: Text('Choose Date'),
              ),
              PopupMenuItem<String>(
                value: 'reset',
                child: Text('Show All'),
              ),
            ],
            icon: Icon(Icons.calendar_today, color: theme.colorScheme.onPrimary),
          ),
        ],

      ),
      body: RefreshIndicator(
        onRefresh: _reloadHistory,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchHistory(),
          builder: (context, snapshot) {
            // Loading from Firestore
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            // If error
            if (snapshot.hasError) {
              return Center(child: Text("Error loading history"));
            }
            // If empty
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(child: Text("No history available"));
            }

            // We have data
            List<Map<String, dynamic>> historyList = snapshot.data!;

            // Filter by date if user picked one
            if (_selectedDate != null) {
              historyList = historyList.where((entry) {
                if (entry.containsKey('timestamp') && entry['timestamp'] != null) {
                  String entryDate = DateFormat('yyyy-MM-dd')
                      .format(entry['timestamp'].toDate());
                  return entryDate == _selectedDate;
                }
                return false;
              }).toList();
            }

            return ListView.builder(
              physics: AlwaysScrollableScrollPhysics(),
              itemCount: historyList.length,
              itemBuilder: (context, index) {
                var entry = historyList[index];
                final imageUrl = entry['image_url'];

                return Card(
                  elevation: 5,
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ExpansionTile(
                    leading: SizedBox(
                      width: 50,
                      height: 50,
                      // If imageUrl is null or missing, show the fallback icon
                      child: imageUrl != null
                          ? FadeInImage.assetNetwork(
                              placeholder: 'assets/icons/image_not_available.png',
                              image: imageUrl,
                              fit: BoxFit.cover,
                              // If there's an error, show the fallback
                              imageErrorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/icons/image_not_available.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          : Image.asset(
                              'assets/icons/image_not_available.png',
                              fit: BoxFit.cover,
                            ),
                    ),
                    title: Text(
                      entry['predictedFood'] ?? "Unknown",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.secondary,
                      ),
                      
                    ),
                    subtitle: entry.containsKey('timestamp') && entry['timestamp'] != null
                        ? Text(
                            "Analyzed on: ${DateFormat('yyyy-MM-dd HH:mm').format(entry['timestamp'].toDate())}",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          )
                        : Text("Timestamp unavailable"),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          entry['nutritional_info'] ?? "No analysis available",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: theme.colorScheme.onSurface,
                          )
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

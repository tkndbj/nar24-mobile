// lib/models/search_entry.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class SearchEntry {
  final String searchTerm;
  final DateTime? timestamp;
  final String userId;
  final String id; 

  SearchEntry({
    required this.searchTerm,
    required this.timestamp,
    required this.userId,
    required this.id,
  });

  factory SearchEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SearchEntry(
      id: doc.id, 
      searchTerm: data['searchTerm'] as String,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      userId: data['userId'] as String,
    );
  }
}

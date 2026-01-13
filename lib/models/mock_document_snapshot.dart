// lib/models/mock_document_snapshot.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MockDocumentSnapshot { // Removed underscore to make it public
  final String id;
  final Map<String, dynamic> _data;

  MockDocumentSnapshot(this.id, this._data);

  Map<String, dynamic>? data() => _data;

  bool get exists => _data.isNotEmpty;

  DocumentReference get reference => FirebaseFirestore.instance.collection('shops').doc(id);
}
import 'package:cloud_firestore/cloud_firestore.dart';

class UserData {
  final String id;
  final String? displayName;
  final String? profileImage;

  UserData({
    required this.id,
    this.displayName,
    this.profileImage,
  });

  factory UserData.fromSnap(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>?;
    return UserData(
      id: snap.id,
      displayName: data?['displayName'] as String?,
      profileImage: data?['profileImage'] as String?,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String type;
  final String? text;
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? content; // For product messages

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.type,
    this.text,
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    required this.timestamp,
    required this.isRead,
    this.content,
  });

  factory ChatMessage.fromSnap(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>;
    return ChatMessage(
      id: snap.id,
      senderId: data['senderId'] as String,
      recipientId: data['recipientId'] as String,
      type: data['type'] as String,
      text: data['text'] as String?,
      imageUrl: data['imageUrl'] as String?,
      fileUrl: data['fileUrl'] as String?,
      fileName: data['fileName'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] as bool? ?? false,
      content: data['content'] as Map<String, dynamic>?,
    );
  }
}

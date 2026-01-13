// lib/utils/notification_helper.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// A helper function to create a localized notification in Firestore.
///
/// [userId]: The ID of the user who will receive the notification.
/// [type]: The type of notification (e.g., 'message', 'new_review').
/// [messages]: A map containing localized messages.
/// [titles]: An optional map containing localized titles.
/// [additionalData]: Any additional data relevant to the notification.
Future<void> createLocalizedNotification({
  required String userId,
  required String type,
  required Map<String, String> messages, // e.g., {'en': '...', 'tr': '...', 'ru': '...'}
  Map<String, String>? titles, // Optional
  Map<String, dynamic>? additionalData, // e.g., productId, reviewId
}) async {
  // Validate that all required languages are provided
  const supportedLanguages = ['en', 'tr', 'ru'];
  for (var lang in supportedLanguages) {
    if (!messages.containsKey(lang)) {
      throw ArgumentError('Missing message for language: $lang');
    }
    if (titles != null && !titles.containsKey(lang)) {
      throw ArgumentError('Missing title for language: $lang');
    }
  }

  // Prepare notification data
  Map<String, dynamic> notificationData = {
    'userId': userId,
    'type': type,
    'timestamp': FieldValue.serverTimestamp(),
    'isRead': false,
    // Add localized messages
    'message_en': messages['en']!,
    'message_tr': messages['tr']!,
    'message_ru': messages['ru']!,
    // Add localized titles if provided
    if (titles != null) ...{
      'title_en': titles['en']!,
      'title_tr': titles['tr']!,
      'title_ru': titles['ru']!,
    },
    // Add any additional data
    if (additionalData != null) ...additionalData,
  };

  try {
    // Add notification to user's notifications subcollection
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add(notificationData);
    print('Notification created successfully for user: $userId');
  } catch (e) {
    print('Error creating notification: $e');
    rethrow; // Re-throw the exception after logging
  }
}

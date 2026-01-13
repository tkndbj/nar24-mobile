import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdAnalyticsService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Track when user clicks on an ad
  static Future<void> trackAdClick({
    required String adId,
    required String adType,
    String? linkedType,
    String? linkedId,
  }) async {
    try {
      final callable = _functions.httpsCallable('trackAdClick');

      await callable.call({
        'adId': adId,
        'adType': adType,
        'linkedType': linkedType,
        'linkedId': linkedId,
      });

      debugPrint('✅ Ad click tracked: $adId');
    } catch (e) {
      debugPrint('❌ Error tracking ad click: $e');
      // Don't throw - analytics failures shouldn't break UX
    }
  }

  /// Get analytics for an ad (reading directly from Firestore)
  static Future<Map<String, dynamic>?> getAdAnalytics({
    required String adId,
    required String adType,
  }) async {
    try {
      // Get collection name based on ad type
      String collectionName;
      switch (adType) {
        case 'topBanner':
          collectionName = 'market_top_ads_banners';
          break;
        case 'thinBanner':
          collectionName = 'market_thin_banners';
          break;
        case 'marketBanner':
          collectionName = 'market_banners';
          break;
        default:
          collectionName = 'market_banners';
      }

      // Read the ad document directly
      final adDoc = await _firestore.collection(collectionName).doc(adId).get();

      if (!adDoc.exists) {
        debugPrint('❌ Ad not found: $adId');
        return null;
      }

      final data = adDoc.data() as Map<String, dynamic>;

      // Extract analytics data
      final totalClicks = data['totalClicks'] ?? 0;
      final totalConversions = data['totalConversions'] ?? 0;
      final conversionRate =
          totalClicks > 0 ? (totalConversions / totalClicks) * 100 : 0.0;

      // Extract demographics
      final demographics = data['demographics'] as Map<String, dynamic>? ?? {};
      final gender = demographics['gender'] as Map<String, dynamic>? ?? {};
      final ageGroups =
          demographics['ageGroups'] as Map<String, dynamic>? ?? {};

      // Get recent clicks for details (optional - can be removed if you don't need it)
      final clicksSnapshot = await _firestore
          .collection(collectionName)
          .doc(adId)
          .collection('clicks')
          .orderBy('clickedAt', descending: true)
          .limit(100)
          .get();

      final clickDetails = clicksSnapshot.docs.map((doc) {
        final clickData = doc.data();
        return {
          'userId': clickData['userId'],
          'gender': clickData['gender'],
          'ageGroup': clickData['ageGroup'],
          'clickedAt': clickData['clickedAt'],
          'converted': clickData['converted'] ?? false,
          'convertedAt': clickData['convertedAt'],
        };
      }).toList();

      return {
        'totalClicks': totalClicks,
        'totalConversions': totalConversions,
        'conversionRate': double.parse(conversionRate.toStringAsFixed(2)),
        'demographics': {
          'gender': gender,
          'ageGroups': ageGroups,
        },
        'lastClickedAt': data['lastClickedAt'],
        'lastConvertedAt': data['lastConvertedAt'],
        'clickDetails': clickDetails,
      };
    } catch (e) {
      debugPrint('❌ Error getting ad analytics: $e');
      return null;
    }
  }

  /// Get daily snapshots for trend analysis
  static Stream<List<Map<String, dynamic>>> getDailySnapshots({
    required String adId,
    required String adType,
    int limit = 30,
  }) {
    String collectionName;
    switch (adType) {
      case 'topBanner':
        collectionName = 'market_top_ads_banners';
        break;
      case 'thinBanner':
        collectionName = 'market_thin_banners';
        break;
      case 'marketBanner':
        collectionName = 'market_banners';
        break;
      default:
        collectionName = 'market_banners';
    }

    return _firestore
        .collection(collectionName)
        .doc(adId)
        .collection('daily_snapshots')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'date': (data['date'] as Timestamp).toDate(),
          'totalClicks': data['totalClicks'] ?? 0,
          'totalConversions': data['totalConversions'] ?? 0,
          'conversionRate': data['conversionRate'] ?? 0.0,
          'demographics': data['demographics'] ?? {},
        };
      }).toList();
    });
  }
}

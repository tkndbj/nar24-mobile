// lib/services/personalized_feed_service.dart
// Production-ready personalized feed service with caching and fallbacks

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for fetching personalized product recommendations
///
/// Features:
/// - Personalized feed for authenticated users
/// - Trending products fallback for unauthenticated/new users
/// - In-memory and disk caching for performance
/// - Graceful degradation on errors
/// - Automatic cache invalidation
class PersonalizedFeedService {
  static PersonalizedFeedService? _instance;
  static PersonalizedFeedService get instance {
    _instance ??= PersonalizedFeedService._internal();
    return _instance!;
  }

  PersonalizedFeedService._internal();

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // In-memory cache
  List<String>? _cachedPersonalizedFeed;
  List<String>? _cachedTrendingProducts;
  DateTime? _personalizedCacheExpiry;
  DateTime? _trendingCacheExpiry;

  // Cache durations
  static const Duration _personalizedCacheDuration = Duration(hours: 6);
  static const Duration _trendingCacheDuration = Duration(hours: 2);

  // SharedPreferences keys
  static const String _keyPersonalizedFeed = 'personalized_feed_cache';
  static const String _keyPersonalizedExpiry = 'personalized_feed_expiry';
  static const String _keyTrendingProducts = 'trending_products_cache';
  static const String _keyTrendingExpiry = 'trending_products_expiry';

  SharedPreferences? _prefs;

  /// Initialize the service (call once at app startup)
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadCachedData();
      debugPrint('✅ PersonalizedFeedService initialized');
    } catch (e) {
      debugPrint('⚠️ PersonalizedFeedService init error: $e');
    }
  }

  /// Load cached data from disk
  Future<void> _loadCachedData() async {
    try {
      // Load personalized feed cache
      final personalizedFeed = _prefs?.getStringList(_keyPersonalizedFeed);
      final personalizedExpiry = _prefs?.getInt(_keyPersonalizedExpiry);

      if (personalizedFeed != null && personalizedExpiry != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(personalizedExpiry);
        if (expiry.isAfter(DateTime.now())) {
          _cachedPersonalizedFeed = personalizedFeed;
          _personalizedCacheExpiry = expiry;
          debugPrint(
              '📥 Loaded ${personalizedFeed.length} personalized products from cache');
        }
      }

      // Load trending products cache
      final trendingProducts = _prefs?.getStringList(_keyTrendingProducts);
      final trendingExpiry = _prefs?.getInt(_keyTrendingExpiry);

      if (trendingProducts != null && trendingExpiry != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(trendingExpiry);
        if (expiry.isAfter(DateTime.now())) {
          _cachedTrendingProducts = trendingProducts;
          _trendingCacheExpiry = expiry;
          debugPrint(
              '📥 Loaded ${trendingProducts.length} trending products from cache');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading cached data: $e');
    }
  }

  /// Save data to cache
  Future<void> _saveToCache(
    List<String> products,
    bool isPersonalized,
  ) async {
    try {
      final expiry = DateTime.now().add(
        isPersonalized ? _personalizedCacheDuration : _trendingCacheDuration,
      );

      if (isPersonalized) {
        await _prefs?.setStringList(_keyPersonalizedFeed, products);
        await _prefs?.setInt(
            _keyPersonalizedExpiry, expiry.millisecondsSinceEpoch);
        _cachedPersonalizedFeed = products;
        _personalizedCacheExpiry = expiry;
      } else {
        await _prefs?.setStringList(_keyTrendingProducts, products);
        await _prefs?.setInt(_keyTrendingExpiry, expiry.millisecondsSinceEpoch);
        _cachedTrendingProducts = products;
        _trendingCacheExpiry = expiry;
      }
    } catch (e) {
      debugPrint('⚠️ Error saving to cache: $e');
    }
  }

  /// Check if cached data is still valid
  bool _isCacheValid(bool isPersonalized) {
    final expiry =
        isPersonalized ? _personalizedCacheExpiry : _trendingCacheExpiry;
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  /// Get trending products (fallback for unauthenticated/new users)
  Future<List<String>> _getTrendingProducts() async {
    try {
      // Return cached trending if still valid
      if (_isCacheValid(false) && _cachedTrendingProducts != null) {
        debugPrint(
            '✅ Returning cached trending products (${_cachedTrendingProducts!.length})');
        return _cachedTrendingProducts!;
      }

      debugPrint('📡 Fetching trending products from Firestore...');

      final trendingDoc =
          await _firestore.collection('trending_products').doc('global').get();

      if (!trendingDoc.exists) {
        debugPrint('⚠️ Trending products not found');
        return [];
      }

      final data = trendingDoc.data()!;
      final products = List<String>.from(data['products'] ?? []);

      if (products.isEmpty) {
        debugPrint('⚠️ Trending products list is empty');
        return [];
      }

      // Cache the results
      await _saveToCache(products, false);

      debugPrint('✅ Fetched ${products.length} trending products');
      return products;
    } catch (e) {
      debugPrint('❌ Error fetching trending products: $e');

      // Return cached data even if expired (better than nothing)
      if (_cachedTrendingProducts != null &&
          _cachedTrendingProducts!.isNotEmpty) {
        debugPrint('⚠️ Using expired trending cache as fallback');
        return _cachedTrendingProducts!;
      }

      return [];
    }
  }

  /// Get personalized products for authenticated user
  Future<List<String>> _getPersonalizedProducts(String userId) async {
    try {
      // Return cached personalized feed if still valid
      if (_isCacheValid(true) && _cachedPersonalizedFeed != null) {
        debugPrint(
            '✅ Returning cached personalized feed (${_cachedPersonalizedFeed!.length})');
        return _cachedPersonalizedFeed!;
      }

      debugPrint('📡 Fetching personalized feed from Firestore...');

      final feedDoc = await _firestore
          .collection('user_profiles')
          .doc(userId)
          .collection('personalized_feed')
          .doc('current')
          .get();

      if (!feedDoc.exists) {
        debugPrint('⚠️ Personalized feed not found, using trending');
        return _getTrendingProducts();
      }

      final data = feedDoc.data()!;

      // Check if feed is stale (>3 days old as buffer for 2-day refresh)
      final lastComputed = data['lastComputed'] as Timestamp?;
      if (lastComputed != null) {
        final age = DateTime.now().difference(lastComputed.toDate());
        if (age.inDays > 3) {
          debugPrint(
              '⚠️ Personalized feed is stale (${age.inDays} days), using trending');
          return _getTrendingProducts();
        }
      }

      final products = List<String>.from(data['productIds'] ?? []);

      if (products.isEmpty) {
        debugPrint('⚠️ Personalized feed is empty, using trending');
        return _getTrendingProducts();
      }

      // Cache the results
      await _saveToCache(products, true);

      debugPrint('✅ Fetched ${products.length} personalized products');
      return products;
    } catch (e) {
      debugPrint('❌ Error fetching personalized feed: $e');

      // Return cached data even if expired (better than nothing)
      if (_cachedPersonalizedFeed != null &&
          _cachedPersonalizedFeed!.isNotEmpty) {
        debugPrint('⚠️ Using expired personalized cache as fallback');
        return _cachedPersonalizedFeed!;
      }

      // Fall back to trending
      return _getTrendingProducts();
    }
  }

  /// Get product IDs for the user (personalized or trending)
  ///
  /// This is the main method to call from your UI.
  ///
  /// Returns:
  /// - Personalized products (200 items) for authenticated users with sufficient activity
  /// - Trending products (200 items) for unauthenticated users or as fallback
  ///
  /// Example:
  /// ```dart
  /// final productIds = await PersonalizedFeedService.instance.getProductIds();
  /// // Use productIds to fetch full product details from Firestore
  /// ```
  Future<List<String>> getProductIds() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        debugPrint('👤 User not authenticated, using trending products');
        return _getTrendingProducts();
      }

      // Try personalized feed first
      return await _getPersonalizedProducts(user.uid);
    } catch (e) {
      debugPrint('❌ Error in getProductIds: $e');

      // Final fallback: return cached trending or empty
      if (_cachedTrendingProducts != null &&
          _cachedTrendingProducts!.isNotEmpty) {
        debugPrint('⚠️ Using trending cache as final fallback');
        return _cachedTrendingProducts!;
      }

      return [];
    }
  }

  /// Force refresh personalized feed (bypass cache)
  ///
  /// Use this when user performs significant actions that might change preferences
  /// (e.g., completing a purchase, adding many items to cart)
  Future<List<String>> forceRefresh() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        // Clear trending cache
        _cachedTrendingProducts = null;
        _trendingCacheExpiry = null;
        return _getTrendingProducts();
      }

      // Clear personalized cache
      _cachedPersonalizedFeed = null;
      _personalizedCacheExpiry = null;

      return await _getPersonalizedProducts(user.uid);
    } catch (e) {
      debugPrint('❌ Error in forceRefresh: $e');
      return [];
    }
  }

  /// Get just the trending products (useful for "Trending Now" sections)
  Future<List<String>> getTrendingProductIds() async {
    return _getTrendingProducts();
  }

  /// Clear all caches (call on logout)
  Future<void> clearCache() async {
    try {
      _cachedPersonalizedFeed = null;
      _cachedTrendingProducts = null;
      _personalizedCacheExpiry = null;
      _trendingCacheExpiry = null;

      await _prefs?.remove(_keyPersonalizedFeed);
      await _prefs?.remove(_keyPersonalizedExpiry);
      await _prefs?.remove(_keyTrendingProducts);
      await _prefs?.remove(_keyTrendingExpiry);

      debugPrint('🧹 Cleared all feed caches');
    } catch (e) {
      debugPrint('⚠️ Error clearing cache: $e');
    }
  }

  /// Check if user has a personalized feed
  Future<bool> hasPersonalizedFeed() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Check cache first
      if (_isCacheValid(true) && _cachedPersonalizedFeed != null) {
        return true;
      }

      // Check Firestore
      final feedDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .collection('personalized_feed')
          .doc('current')
          .get();

      return feedDoc.exists;
    } catch (e) {
      debugPrint('⚠️ Error checking personalized feed: $e');
      return false;
    }
  }

  /// Get feed metadata (for debugging/analytics)
  Future<Map<String, dynamic>?> getFeedMetadata() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final feedDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .collection('personalized_feed')
          .doc('current')
          .get();

      if (!feedDoc.exists) return null;

      final data = feedDoc.data()!;
      return {
        'lastComputed': (data['lastComputed'] as Timestamp?)?.toDate(),
        'productsCount': (data['productIds'] as List?)?.length ?? 0,
        'avgScore': data['stats']?['avgScore'],
        'topCategories': data['stats']?['topCategories'],
        'version': data['version'],
      };
    } catch (e) {
      debugPrint('⚠️ Error fetching feed metadata: $e');
      return null;
    }
  }
}

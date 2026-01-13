import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/market_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ✅ NEW: Page impression data class
class PageImpression {
  final String screenName;
  final DateTime timestamp;

  PageImpression({
    required this.screenName,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'screenName': screenName,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory PageImpression.fromJson(Map<String, dynamic> json) => PageImpression(
    screenName: json['screenName'] as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
  );
}

class ImpressionRecord {
  final String productId;
  final String screenName;
  final DateTime timestamp;

  ImpressionRecord({
    required this.productId,
    required this.screenName,
    required this.timestamp,
  });
}

class ImpressionBatcher {
  static final _instance = ImpressionBatcher._internal();
  factory ImpressionBatcher() => _instance;
  ImpressionBatcher._internal();

  // Buffers
  final List<ImpressionRecord> _impressionBuffer = [];
  
  // ✅ NEW: Track per-page impressions per user
  final Map<String, List<PageImpression>> _pageImpressions = {};

  Timer? _batchTimer;
  Timer? _cleanupTimer;
  MarketProvider? _marketProvider;

  // ✅ NEW: Current user tracking
  String? _currentUserId;

  // Configuration (matching web)
  static const Duration _batchInterval = Duration(seconds: 30);
  static const Duration _impressionCooldown = Duration(hours: 1); // ✅ Changed to 1 hour
  static const int _maxBatchSize = 100;
  static const int _maxImpressionsPerHour = 4; // ✅ NEW: Max 4 per hour
  static const int _maxRetries = 3;

  int _retryCount = 0;
  bool _isDisposed = false;

  // ✅ NEW: Storage key prefix
  static const String _pageImpressionsPrefix = 'page_impressions_';

  void initialize(MarketProvider provider) {
    _marketProvider = provider;
    _setCurrentUser();
    _startCleanup();
  }

  // ✅ NEW: Set current user and load their data
  void _setCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    final newUserId = user?.uid;
    
    if (_currentUserId != newUserId) {
      debugPrint('👤 ImpressionBatcher: User changed from $_currentUserId to $newUserId');
      
      // Clear in-memory data when user changes
      _pageImpressions.clear();
      _currentUserId = newUserId;
      
      // Load data for new user
      if (newUserId != null) {
        _loadPageImpressions();
      }
    }
  }

  // ✅ NEW: Get storage key for current user
  String _getStorageKey() {
    final userId = _currentUserId ?? 'anonymous';
    return '$_pageImpressionsPrefix$userId';
  }

  // ✅ NEW: Load page impressions from SharedPreferences
  Future<void> _loadPageImpressions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = _getStorageKey();
      final stored = prefs.getString(storageKey);
      
      if (stored != null) {
        final data = Map<String, dynamic>.from(jsonDecode(stored));
        final now = DateTime.now();
        int expiredCount = 0;
        
        data.forEach((productId, pages) {
          final List<PageImpression> validPages = [];
          
          for (final page in (pages as List)) {
            final impression = PageImpression.fromJson(page);
            final age = now.difference(impression.timestamp);
            
            if (age < _impressionCooldown) {
              validPages.add(impression);
            } else {
              expiredCount++;
            }
          }
          
          if (validPages.isNotEmpty) {
            _pageImpressions[productId] = validPages;
          }
        });
        
        debugPrint('📊 Loaded ${_pageImpressions.length} products with impressions for user $_currentUserId ($expiredCount expired)');
      }
    } catch (e) {
      debugPrint('Error loading page impressions: $e');
    }
  }

  // ✅ NEW: Persist page impressions
  Future<void> _persistPageImpressions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = _getStorageKey();
      
      final data = <String, dynamic>{};
      _pageImpressions.forEach((productId, pages) {
        data[productId] = pages.map((p) => p.toJson()).toList();
      });
      
      await prefs.setString(storageKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Error persisting page impressions: $e');
    }
  }

  void _startCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _cleanupExpiredImpressions();
    });
  }

  // ✅ NEW: Cleanup expired impressions
  void _cleanupExpiredImpressions() {
    final now = DateTime.now();
    int cleaned = 0;
    
    final keysToRemove = <String>[];
    
    _pageImpressions.forEach((productId, pages) {
      final validPages = pages.where((page) {
        final age = now.difference(page.timestamp);
        if (age < _impressionCooldown) {
          return true;
        } else {
          cleaned++;
          return false;
        }
      }).toList();
      
      if (validPages.isEmpty) {
        keysToRemove.add(productId);
      } else {
        _pageImpressions[productId] = validPages;
      }
    });
    
    for (final key in keysToRemove) {
      _pageImpressions.remove(key);
    }
    
    if (cleaned > 0) {
      debugPrint('🧹 Cleaned $cleaned expired page impressions for user $_currentUserId');
      _persistPageImpressions();
    }
  }

  // ✅ UPDATED: Add impression with page tracking
  void addImpression(String productId, {String? screenName}) {
    // ✅ Update current user (in case they logged in/out)
    _setCurrentUser();
    
    final now = DateTime.now();
    final currentScreen = screenName ?? 'unknown';
    
    // Get existing page impressions for this product
    final existingPages = _pageImpressions[productId] ?? [];
    
    // Clean old impressions (> 1 hour)
    final validPages = existingPages.where((page) {
      final age = now.difference(page.timestamp);
      return age < _impressionCooldown;
    }).toList();
    
    // Check if already recorded on THIS SCREEN
    final alreadyRecordedOnThisScreen = validPages.any((page) {
      return page.screenName == currentScreen;
    });
    
    if (alreadyRecordedOnThisScreen) {
      debugPrint('⏳ Product $productId already recorded on screen $currentScreen for user $_currentUserId');
      return;
    }
    
    // ✅ NEW: Check max impressions per hour
    if (validPages.length >= _maxImpressionsPerHour) {
      final oldestImpression = validPages.first;
      final remainingMs = _impressionCooldown.inMilliseconds - 
                          now.difference(oldestImpression.timestamp).inMilliseconds;
      final remainingMinutes = (remainingMs / 60000).ceil();
      
      debugPrint('⚠️ Product $productId has reached max impressions ($_maxImpressionsPerHour) for user $_currentUserId. Wait ${remainingMinutes}m');
      return;
    }

    // Record new impression
    validPages.add(PageImpression(
      screenName: currentScreen,
      timestamp: now,
    ));
    
    _pageImpressions[productId] = validPages;
    
    // Add to buffer for sending
    _impressionBuffer.add(ImpressionRecord(
      productId: productId,
      screenName: currentScreen,
      timestamp: now,
    ));
    
    // Persist
    _persistPageImpressions();
    
    debugPrint('✅ Recorded impression #${validPages.length} for product $productId on screen $currentScreen by user $_currentUserId (${_maxImpressionsPerHour - validPages.length} remaining in this hour)');

    _scheduleBatch();

    if (_impressionBuffer.length >= _maxBatchSize) {
      debugPrint('⚠️ Buffer size limit reached, forcing flush');
      flush();
    }
  }

  void _scheduleBatch() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchInterval, _sendBatch);
  }

  int? _calculateAge(Timestamp? birthDate) {
    if (birthDate == null) return null;
    try {
      final birth = birthDate.toDate();
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age >= 0 ? age : null;
    } catch (e) {
      debugPrint('Error calculating age: $e');
      return null;
    }
  }

  Future<void> _sendBatch() async {
    if (_impressionBuffer.isEmpty || _marketProvider == null) return;

    // ✅ CHANGED: Extract product IDs from records
    final recordsToSend = List<ImpressionRecord>.from(_impressionBuffer);
    final idsToSend = recordsToSend.map((r) => r.productId).toList();
    
    _impressionBuffer.clear();

    try {
      final profileData = _marketProvider!.userProvider.profileData;
      final userGender = profileData?['gender'] as String?;
      final birthDate = profileData?['birthDate'] as Timestamp?;
      final userAge = _calculateAge(birthDate);

      await _marketProvider!.incrementImpressionCount(
        productIds: idsToSend, // ✅ Sends all IDs (including duplicates)
        userGender: userGender,
        userAge: userAge,
      );

      debugPrint(
          '📊 Sent batch of ${recordsToSend.length} impressions from user $_currentUserId - Gender: ${userGender ?? 'unknown'}, Age: ${userAge ?? 'unknown'}');
      _retryCount = 0;
    } catch (e) {
      debugPrint('❌ Error sending impression batch: $e');

      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delay = Duration(seconds: 2 * _retryCount);

        debugPrint(
            '🔄 Retrying impression batch in ${delay.inSeconds}s (attempt $_retryCount/$_maxRetries)');

        // ✅ CHANGED: Re-add failed records
        _impressionBuffer.addAll(recordsToSend);

        Future.delayed(delay, () {
          if (!_isDisposed) _sendBatch();
        });
      } else {
        debugPrint('❌ Max retries reached, dropping ${recordsToSend.length} impressions');
        _retryCount = 0;
      }
    }
  }

  Future<void> flush() async {
    _batchTimer?.cancel();
    await _sendBatch();
  }

  void dispose() {
    _isDisposed = true;
    _batchTimer?.cancel();
    _cleanupTimer?.cancel();
    _impressionBuffer.clear();
    _pageImpressions.clear();
    _marketProvider = null;
  }
}

// ✅ UPDATED: BoostedVisibilityWrapper with screen name support
class BoostedVisibilityWrapper extends StatefulWidget {
  final String productId;
  final Widget child;
  final String? screenName; // ✅ NEW: Screen identifier

  const BoostedVisibilityWrapper({
    Key? key,
    required this.productId,
    required this.child,
    this.screenName, // ✅ NEW
  }) : super(key: key);

  @override
  _BoostedVisibilityWrapperState createState() =>
      _BoostedVisibilityWrapperState();
}

class _BoostedVisibilityWrapperState extends State<BoostedVisibilityWrapper> {
  bool _hasRecordedImpression = false;
  static final _batcher = ImpressionBatcher();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_batcher._marketProvider == null) {
      final marketProvider =
          Provider.of<MarketProvider>(context, listen: false);
      _batcher.initialize(marketProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('boosted-${widget.productId}'),
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.5) {
          if (!_hasRecordedImpression) {
            _batcher.addImpression(
              widget.productId,
              screenName: widget.screenName, // ✅ PASS screen name
            );
            _hasRecordedImpression = true;

            // ✅ CHANGED: Reset after 1 second (page-level cooldown only)
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                _hasRecordedImpression = false;
              }
            });
          }
        }
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _hasRecordedImpression = false;
    super.dispose();
  }
}
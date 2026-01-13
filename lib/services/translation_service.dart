// lib/services/translation_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class TranslationService {
  // Singleton pattern
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  // Your Cloud Function URL - update after deployment
  static const String _baseUrl = 
      'https://europe-west3-emlak-mobile-app.cloudfunctions.net';

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // In-memory cache
  final Map<String, Map<String, String>> _cache = {};

  /// Translate a single text
  Future<String> translate(String text, String targetLanguage) async {
    // Check cache first
    final cacheKey = _generateCacheKey(text);
    if (_cache[cacheKey]?[targetLanguage] != null) {
      return _cache[cacheKey]![targetLanguage]!;
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw TranslationException('User not authenticated');
    }

    // Get fresh ID token
    final idToken = await user.getIdToken();
    if (idToken == null) {
      throw TranslationException('Failed to get authentication token');
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/translateText'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'text': text,
          'targetLanguage': targetLanguage,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translation = data['translation'] as String;

        // Cache the result
        _cache[cacheKey] ??= {};
        _cache[cacheKey]![targetLanguage] = translation;

        return translation;
      } else if (response.statusCode == 429) {
        final data = jsonDecode(response.body);
        throw RateLimitException(
          data['error'] ?? 'Rate limit exceeded',
          retryAfter: data['retryAfter'],
        );
      } else if (response.statusCode == 401) {
        throw TranslationException('Authentication failed');
      } else {
        final data = jsonDecode(response.body);
        throw TranslationException(data['error'] ?? 'Translation failed');
      }
    } catch (e) {
      if (e is TranslationException) rethrow;
      debugPrint('Translation error: $e');
      throw TranslationException('Network error: ${e.toString()}');
    }
  }

  /// Translate multiple texts at once (more efficient)
  Future<List<String>> translateBatch(
    List<String> texts,
    String targetLanguage,
  ) async {
    if (texts.isEmpty) return [];
    if (texts.length > 5) {
      throw TranslationException('Maximum 5 texts per batch');
    }

    // Check cache for all texts
    final results = <String?>[];
    final uncachedTexts = <String>[];
    final uncachedIndices = <int>[];

    for (int i = 0; i < texts.length; i++) {
      final cacheKey = _generateCacheKey(texts[i]);
      final cached = _cache[cacheKey]?[targetLanguage];
      if (cached != null) {
        results.add(cached);
      } else {
        results.add(null);
        uncachedTexts.add(texts[i]);
        uncachedIndices.add(i);
      }
    }

    // If all cached, return immediately
    if (uncachedTexts.isEmpty) {
      return results.cast<String>();
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw TranslationException('User not authenticated');
    }

    final idToken = await user.getIdToken();
    if (idToken == null) {
      throw TranslationException('Failed to get authentication token');
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/translateBatch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'texts': uncachedTexts,
          'targetLanguage': targetLanguage,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translations = List<String>.from(data['translations']);

        // Merge with cached results and update cache
        for (int i = 0; i < uncachedIndices.length; i++) {
          final originalIndex = uncachedIndices[i];
          final translation = translations[i];
          results[originalIndex] = translation;

          // Cache the result
          final cacheKey = _generateCacheKey(texts[originalIndex]);
          _cache[cacheKey] ??= {};
          _cache[cacheKey]![targetLanguage] = translation;
        }

        return results.cast<String>();
      } else if (response.statusCode == 429) {
        throw RateLimitException('Rate limit exceeded');
      } else {
        throw TranslationException('Batch translation failed');
      }
    } catch (e) {
      if (e is TranslationException) rethrow;
      throw TranslationException('Network error: ${e.toString()}');
    }
  }

  /// Generate a short cache key from text
  String _generateCacheKey(String text) {
    // Use first 100 chars + length as key to avoid huge keys
    final truncated = text.length > 100 ? text.substring(0, 100) : text;
    return '${truncated.hashCode}_${text.length}';
  }

  /// Check if translation is cached
  bool isCached(String text, String targetLanguage) {
    final cacheKey = _generateCacheKey(text);
    return _cache[cacheKey]?[targetLanguage] != null;
  }

  /// Get cached translation if available
  String? getCached(String text, String targetLanguage) {
    final cacheKey = _generateCacheKey(text);
    return _cache[cacheKey]?[targetLanguage];
  }

  /// Clear all cached translations
  void clearCache() {
    _cache.clear();
  }
}

/// Base exception for translation errors
class TranslationException implements Exception {
  final String message;
  TranslationException(this.message);

  @override
  String toString() => message;
}

/// Exception for rate limit errors
class RateLimitException extends TranslationException {
  final int? retryAfter;

  RateLimitException(super.message, {this.retryAfter});
}
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category_structure.dart';

class CategoryCacheService extends ChangeNotifier {
  static const _versionKey = 'category_version';
  static const _dataKey = 'category_data';

  CategoryStructure? _structure;
  CategoryStructure? get structure => _structure;
  bool get isLoaded => _structure != null;

  Future<void> initialize() async {
    if (_structure != null) return; // Already loaded in memory

    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getString(_versionKey);

    try {
      // 1 read: check version
      final meta = await FirebaseFirestore.instance
          .collection('categories')
          .doc('meta')
          .get();

      final remoteVersion = meta.data()?['version'] as String?;

      if (remoteVersion != null && remoteVersion == localVersion) {
        // Version matches → use local cache, zero extra reads
        final cached = prefs.getString(_dataKey);
        if (cached != null) {
          // ✅ CHANGE 1: wrap in try/catch — corrupt JSON won't crash the app
          try {
            _structure = CategoryStructure.fromJson(jsonDecode(cached));
            notifyListeners();
            return;
          } catch (e) {
            debugPrint('CategoryCacheService: corrupt cache, re-fetching: $e');
            // Fall through to fetch fresh from Firestore
          }
        }
      }

      // Version mismatch OR corrupt cache → fetch full structure (1 more read)
      final structSnap = await FirebaseFirestore.instance
          .collection('categories')
          .doc('structure')
          .get();

      if (structSnap.exists) {
        final data = structSnap.data()!;
        await prefs.setString(_dataKey, jsonEncode(data));
        await prefs.setString(_versionKey, remoteVersion ?? '');
        _structure = CategoryStructure.fromJson(data);
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('CategoryCacheService: Firestore error: $e');
      // Fall through to local cache
      final cached = prefs.getString(_dataKey);
      if (cached != null) {
        // ✅ CHANGE 2: wrap in try/catch — corrupt JSON in fallback won't crash either
        try {
          _structure = CategoryStructure.fromJson(jsonDecode(cached));
          notifyListeners();
          return;
        } catch (e) {
          debugPrint('CategoryCacheService: corrupt cache in fallback: $e');
          // Fall through to bundled defaults
        }
      }
    }

    // Last resort: use bundled defaults
    _structure = CategoryStructure.defaults();
    notifyListeners();
  }
}
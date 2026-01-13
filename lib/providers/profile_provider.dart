// lib/profile_provider.dart
// FIXED VERSION - Improved refresh handling

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';

/// Error types for profile loading - used to show appropriate UI
enum ProfileErrorType {
  none,
  networkUnavailable, // Transient - can retry
  unknown, // Unexpected error
}

class ProfileProvider with ChangeNotifier {
  User? _currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  ProfileErrorType _errorType = ProfileErrorType.none;
  bool _hasValidCachedData = false;
  StreamSubscription<User?>? _authSubscription;

  ProfileProvider() {
    _listenToAuthChanges();
  }

  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProfileErrorType get errorType => _errorType;
  bool get hasValidCachedData => _hasValidCachedData;

  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (User? user) async {
        _currentUser = user;
        if (user != null) {
          await _fetchUserData();
        } else {
          _userData = null;
          _isLoading = false;
          _errorMessage = null;
          notifyListeners();
        }
      },
      onError: (error) {
        _isLoading = false;
        _errorMessage = 'Authentication error: $error';
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Checks if an error is a transient network error that can be retried
  bool _isTransientError(dynamic error) {
    if (error is FirebaseException) {
      const transientCodes = [
        'unavailable',
        'deadline-exceeded',
        'resource-exhausted',
        'aborted',
        'internal',
      ];
      return transientCodes.contains(error.code);
    }
    if (error is TimeoutException) {
      return true;
    }
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('unavailable') ||
        errorStr.contains('timeout') ||
        errorStr.contains('network') ||
        errorStr.contains('connection');
  }

  Future<void> _fetchUserData({bool forceServer = false}) async {
    if (_currentUser == null) return;

    _isLoading = true;
    _errorMessage = null;
    _errorType = ProfileErrorType.none;
    notifyListeners();

    // STEP 1: Try to load from cache first for instant UI (unless forcing server)
    bool cacheLoaded = false;
    if (!forceServer) {
      cacheLoaded = await _loadFromCache();
    }

    // STEP 2: Fetch from server with robust retry logic
    await _fetchFromServerWithRetry(
        hadCacheData: cacheLoaded, forceServer: forceServer);
  }

  /// Attempts to load user data from Firestore cache
  /// Returns true if cache had valid data
  Future<bool> _loadFromCache() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get(const GetOptions(source: Source.cache));

      if (doc.exists && doc.data() != null) {
        _userData = doc.data() as Map<String, dynamic>;
        _hasValidCachedData = true;
        _isLoading = false;
        _errorMessage = null;
        _errorType = ProfileErrorType.none;
        notifyListeners();
        debugPrint('✅ Profile loaded from cache');
        return true;
      }
    } catch (e) {
      debugPrint('ℹ️ No cached profile data available');
    }
    return false;
  }

  /// Fetches user data from server with exponential backoff retry
  Future<void> _fetchFromServerWithRetry({
    required bool hadCacheData,
    bool forceServer = false,
  }) async {
    const maxRetries = 5;
    const baseDelayMs = 500;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // ✅ FIX: Use Source.server when forceServer is true
        // This ensures we get fresh data after updates
        final GetOptions options = forceServer
            ? const GetOptions(source: Source.server)
            : const GetOptions(); // Default lets SDK decide

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .get(options)
            .timeout(const Duration(seconds: 15));

        if (doc.exists && doc.data() != null) {
          _userData = doc.data() as Map<String, dynamic>;
          _hasValidCachedData = true;
          _errorMessage = null;
          _errorType = ProfileErrorType.none;
          _isLoading = false;
          notifyListeners();
          debugPrint(
              '✅ Profile loaded from server (attempt $attempt, forceServer=$forceServer)');
          return;
        } else {
          await _createDefaultUserDocument();
          return;
        }
      } catch (e) {
        final isTransient = _isTransientError(e);
        debugPrint(
            '⚠️ Profile fetch attempt $attempt/$maxRetries failed: $e (transient: $isTransient)');

        if (!isTransient) {
          _handleFetchError(e, hadCacheData);
          return;
        }

        if (attempt < maxRetries) {
          final delayMs = baseDelayMs * (1 << (attempt - 1));
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          _handleFetchError(e, hadCacheData);
        }
      }
    }
  }

  void _handleFetchError(dynamic error, bool hadCacheData) {
    final isTransient = _isTransientError(error);

    if (hadCacheData && _userData != null) {
      debugPrint('⚠️ Server fetch failed but using cached data. Error: $error');
      _errorMessage = null;
      _errorType = ProfileErrorType.none;
      _isLoading = false;
      notifyListeners();
      _scheduleBackgroundRefresh();
    } else {
      _errorType = isTransient
          ? ProfileErrorType.networkUnavailable
          : ProfileErrorType.unknown;
      _errorMessage = isTransient ? 'network_unavailable' : 'unknown_error';
      _isLoading = false;
      notifyListeners();
    }
  }

  void _scheduleBackgroundRefresh() {
    Future.delayed(const Duration(seconds: 30), () {
      if (_currentUser != null) {
        _silentRefresh();
      }
    });
  }

  Future<void> _silentRefresh() async {
    if (_currentUser == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists && doc.data() != null) {
        _userData = doc.data() as Map<String, dynamic>;
        _hasValidCachedData = true;
        notifyListeners();
        debugPrint('✅ Silent background refresh successful');
      }
    } catch (e) {
      debugPrint('ℹ️ Silent background refresh failed: $e');
    }
  }

  Future<void> _createDefaultUserDocument() async {
    _userData = {
      'displayName': _currentUser!.displayName ?? 'No Name',
      'email': _currentUser!.email ?? 'No Email',
      'profileImage': null,
      'isVerified': false,
      'isNew': false,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .set(_userData!);
      _hasValidCachedData = true;
    } catch (e) {
      debugPrint('⚠️ Could not create user document: $e');
    }

    _errorMessage = null;
    _errorType = ProfileErrorType.none;
    _isLoading = false;
    notifyListeners();
  }

  /// Manual retry method - called from UI retry button
  Future<void> retryFetch() async {
    if (_currentUser == null) return;
    await _fetchUserData();
  }

  /// ✅ FIX: Enhanced refreshUser that forces server fetch
  /// This ensures fresh data is loaded after profile updates
  Future<void> refreshUser() async {
    if (_currentUser != null) {
      await _currentUser!.reload();
      _currentUser = FirebaseAuth.instance.currentUser;
      // Force server fetch to get the latest data
      await _fetchUserData(forceServer: true);
    }
  }

  /// ✅ FIX: Quick local update for immediate UI feedback
  /// Use this when you know the exact field that changed
  void updateLocalField(String key, dynamic value) {
    if (_userData != null) {
      _userData![key] = value;
      notifyListeners();
    }
  }

  Future<void> uploadProfileImage() async {
    if (_currentUser == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      try {
        _isLoading = true;
        notifyListeners();

        String fileName = 'profileImages/${_currentUser!.uid}';
        Reference reference = FirebaseStorage.instance.ref().child(fileName);
        UploadTask uploadTask = reference.putFile(File(pickedFile.path));
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .update({'profileImage': downloadUrl});

        _userData?['profileImage'] = downloadUrl;
      } catch (e) {
        _errorMessage = 'Error uploading image: $e';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
}

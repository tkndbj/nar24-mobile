// lib/profile_provider.dart
// Consumes user data from UserProvider to avoid duplicate Firestore reads.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../user_provider.dart';

/// Error types for profile loading - used to show appropriate UI
enum ProfileErrorType {
  none,
  networkUnavailable, // Transient - can retry
  unknown, // Unexpected error
}

class ProfileProvider with ChangeNotifier {
  final UserProvider _userProvider;

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  ProfileErrorType _errorType = ProfileErrorType.none;
  bool _hasValidCachedData = false;

  ProfileProvider(this._userProvider) {
    // Sync initial state from UserProvider
    _syncFromUserProvider();
    // Listen for future updates
    _userProvider.addListener(_syncFromUserProvider);
  }

  User? get currentUser => _userProvider.user;
  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProfileErrorType get errorType => _errorType;
  bool get hasValidCachedData => _hasValidCachedData;

  /// Syncs local state from UserProvider's already-fetched user document.
  void _syncFromUserProvider() {
    final profileData = _userProvider.profileData;
    final userProviderLoading = _userProvider.isLoading;
    final user = _userProvider.user;

    bool changed = false;

    // Sync loading state
    if (_isLoading != userProviderLoading) {
      _isLoading = userProviderLoading;
      changed = true;
    }

    // Sync user data
    if (profileData != null) {
      _userData = Map<String, dynamic>.from(profileData);
      _hasValidCachedData = true;
      _errorMessage = null;
      _errorType = ProfileErrorType.none;
      _isLoading = false;
      changed = true;
    } else if (user == null) {
      // Logged out
      if (_userData != null || _errorMessage != null) {
        _userData = null;
        _hasValidCachedData = false;
        _isLoading = false;
        _errorMessage = null;
        _errorType = ProfileErrorType.none;
        changed = true;
      }
    } else if (!userProviderLoading && profileData == null) {
      // UserProvider finished loading but has no data — error state
      if (_errorType == ProfileErrorType.none && _userData == null) {
        _errorType = ProfileErrorType.networkUnavailable;
        _errorMessage = 'network_unavailable';
        _isLoading = false;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _userProvider.removeListener(_syncFromUserProvider);
    super.dispose();
  }

  /// Manual retry — delegates to UserProvider's fetch
  Future<void> retryFetch() async {
    if (_userProvider.user == null) return;
    _isLoading = true;
    _errorMessage = null;
    _errorType = ProfileErrorType.none;
    notifyListeners();
    await _userProvider.refreshUser();
    // _syncFromUserProvider will be called via the listener
  }

  /// Refresh user data — delegates to UserProvider
  Future<void> refreshUser() async {
    await _userProvider.refreshUser();
    // _syncFromUserProvider will be called via the listener
  }

  /// Quick local update for immediate UI feedback
  void updateLocalField(String key, dynamic value) {
    if (_userData != null) {
      _userData![key] = value;
      notifyListeners();
    }
  }

  Future<void> uploadProfileImage() async {
    if (_userProvider.user == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      try {
        _isLoading = true;
        notifyListeners();

        final uid = _userProvider.user!.uid;
        String fileName = 'profileImages/$uid';
        Reference reference = FirebaseStorage.instance.ref().child(fileName);
        UploadTask uploadTask = reference.putFile(File(pickedFile.path));
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'profileImage': downloadUrl});

        _userData?['profileImage'] = downloadUrl;

        // Refresh UserProvider so all consumers get the updated image
        await _userProvider.refreshUser();
      } catch (e) {
        _errorMessage = 'Error uploading image: $e';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
}

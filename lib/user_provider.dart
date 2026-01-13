// lib/user_provider.dart
// FIXED VERSION - Key changes marked with // ✅ FIX

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/lifecycle_aware.dart';
import 'services/app_lifecycle_manager.dart';

class UserProvider with ChangeNotifier, LifecycleAwareMixin {
  User? _user;
  bool _isLoading = true;
  bool _isAdmin = false;
  Map<String, dynamic>? _profileData;
  bool? _profileComplete;

  StreamSubscription<User?>? _authSubscription;
  bool _isResuming = false;

  static const String _profileCompleteKey = 'user_profile_complete';
  static const String _nameCompleteKey = 'user_name_complete';

  bool? _nameComplete;
  bool _isNameSaveInProgress = false;

  // ✅ FIX: Add debounce for background fetches to prevent rapid overwrites
  Timer? _backgroundFetchDebounce;
  static const Duration _backgroundFetchDelay = Duration(milliseconds: 500);

  bool get needsNameCompletion {
    if (!isAppleUser) return false;

    // ✅ FIX: During save, always return false to prevent redirect loops
    if (_isNameSaveInProgress) return false;

    if (_nameComplete != null) return !_nameComplete!;
    if (_profileData == null) return false;

    final displayName = _profileData!['displayName'] as String?;
    final email = _profileData!['email'] as String? ?? _user?.email ?? '';
    final emailPrefix = email.split('@').first;

    return displayName == null ||
        displayName.isEmpty ||
        displayName == 'User' ||
        displayName == 'No Name' ||
        displayName == emailPrefix;
  }

  bool get isNameStateReady {
    // ✅ FIX: Not ready during save operations
    if (_isNameSaveInProgress) return false;
    return !isAppleUser || _nameComplete != null || _profileData != null;
  }

  @override
  LifecyclePriority get lifecyclePriority => LifecyclePriority.critical;

  UserProvider() {
    _isLoading = true;
    _initializeProfileState();
    _setupAuthListener();
    AppLifecycleManager.instance.register(this, name: 'UserProvider');
  }

  Future<void> _initializeProfileState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cachedProfileValue = prefs.getBool(_profileCompleteKey);
      if (cachedProfileValue != null && _profileComplete == null) {
        _profileComplete = cachedProfileValue;
      }

      final cachedNameValue = prefs.getBool(_nameCompleteKey);
      if (cachedNameValue != null && _nameComplete == null) {
        _nameComplete = cachedNameValue;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading cached profile state: $e');
    }
  }

  Future<void> _cacheNameComplete(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_nameCompleteKey, value);
    } catch (e) {
      if (kDebugMode) debugPrint('Error caching name state: $e');
    }
  }

  void setNameComplete(bool complete) {
    if (_nameComplete != complete) {
      _nameComplete = complete;
      _cacheNameComplete(complete);
      notifyListeners();
    }
  }

  void setNameSaveInProgress(bool inProgress) {
    if (_isNameSaveInProgress != inProgress) {
      _isNameSaveInProgress = inProgress;
      // ✅ FIX: Notify listeners so router redirect re-evaluates
      notifyListeners();
    }
  }

  // ✅ FIX: New method to update local profile data immediately
  // This ensures UI reflects changes before Firestore fetch completes
  void updateLocalProfileField(String key, dynamic value) {
    _profileData ??= {};
    _profileData![key] = value;
    notifyListeners();
  }

  Future<void> _cacheProfileComplete(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_profileCompleteKey, value);
    } catch (e) {
      if (kDebugMode) debugPrint('Error caching profile state: $e');
    }
  }

  Future<void> _clearCachedProfileState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileCompleteKey);
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing cached profile state: $e');
    }
  }

  void _setupAuthListener() {
    _authSubscription?.cancel();
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (kDebugMode) debugPrint('🔥 Auth state changed: user=${user?.uid}');
      final wasLoggedOut = _user == null && user != null;
      final wasLoggedIn = _user != null;
      _user = user;
      if (_user != null) {
        await fetchUserData(forceServer: wasLoggedOut && !_isResuming);
      } else if (wasLoggedIn) {
        _resetState();
      } else {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          if (kDebugMode) debugPrint('🔓 No user logged in, stopping loading');
          _isLoading = false;
          notifyListeners();
        } else {
          if (kDebugMode)
            debugPrint('⏳ Auth stream null but currentUser exists, waiting...');
        }
      }
    }, onError: (error) {
      if (kDebugMode) debugPrint('Error in authStateChanges: $error');
      _isLoading = false;
      notifyListeners();
    });
  }

  @override
  Future<void> onPause() async {
    await super.onPause();
    // ✅ FIX: Cancel pending background fetches on pause
    _backgroundFetchDebounce?.cancel();
    if (kDebugMode) {
      debugPrint('⏸️ UserProvider: Paused (auth listener remains active)');
    }
  }

  @override
  Future<void> onResume(Duration pauseDuration) async {
    await super.onResume(pauseDuration);
    _isResuming = true;

    try {
      if (_user != null && _profileComplete == null) {
        final prefs = await SharedPreferences.getInstance();
        final cachedValue = prefs.getBool(_profileCompleteKey);
        if (cachedValue != null) {
          _profileComplete = cachedValue;
          notifyListeners();
        }
      }

      if (_user != null) {
        if (shouldFullRefresh(pauseDuration)) {
          if (kDebugMode) {
            debugPrint(
                '🔄 UserProvider: Long pause detected, background syncing...');
          }
          _backgroundFetchUserData();
        }
      }
    } finally {
      _isResuming = false;
    }
  }

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAdmin => _isAdmin;

  bool get isGoogleUser =>
      _user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  bool get isAppleUser =>
      _user?.providerData.any((p) => p.providerId == 'apple.com') ?? false;

  bool get isSocialUser => isGoogleUser || isAppleUser;

  bool get isProfileStateReady =>
      _profileComplete != null || _profileData != null;

  bool get isProfileComplete {
    if (_profileComplete != null) return _profileComplete!;
    if (_profileData == null) return false;
    return _profileData!['gender'] != null &&
        _profileData!['birthDate'] != null;
  }

  void _resetState() {
    _isAdmin = false;
    _profileData = null;
    _profileComplete = null;
    _isNameSaveInProgress = false;
    _nameComplete = null;
    _isLoading = false;
    _backgroundFetchDebounce?.cancel();
    _clearCachedProfileState();
    _clearCachedNameState();
    notifyListeners();
  }

  Future<void> _clearCachedNameState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_nameCompleteKey);
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing cached name state: $e');
    }
  }

  Future<void> fetchUserData({bool forceServer = false}) async {
    final uid = _user?.uid;
    if (uid == null) {
      if (kDebugMode) debugPrint('⚠️ fetchUserData: No user ID, skipping');
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (kDebugMode)
      debugPrint(
          '📥 fetchUserData: Starting for uid=$uid, forceServer=$forceServer');

    const maxRetries = 3;
    int retryCount = 0;

    if (!forceServer) {
      try {
        final cacheDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));

        if (_user?.uid != uid) return;

        if (cacheDoc.exists) {
          _updateUserDataFromDoc(cacheDoc);
          notifyListeners();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Cache fetch failed or timed out: $e');
      }
    }

    while (retryCount < maxRetries) {
      try {
        final serverDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));

        if (_user?.uid != uid) return;

        if (serverDoc.exists) {
          _updateUserDataFromDoc(serverDoc);
          _syncLanguageToFirestore(uid, serverDoc.data());
        } else {
          await _createDefaultUserDoc();
        }

        if (kDebugMode) debugPrint('✅ fetchUserData: Completed successfully');
        _isLoading = false;
        notifyListeners();
        return;
      } catch (e) {
        retryCount++;
        if (kDebugMode)
          debugPrint('⚠️ fetchUserData: Attempt $retryCount failed: $e');
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 250 * (1 << retryCount)));
          if (_user?.uid != uid) return;
        } else {
          if (kDebugMode)
            debugPrint('❌ fetchUserData: All retries failed, stopping loading');
          _isLoading = false;
          notifyListeners();
        }
      }
    }
  }

  void _syncLanguageToFirestore(String uid, Map<String, dynamic>? userData) {
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final localLanguage = prefs.getString('locale');
        final firestoreLanguage = userData?['languageCode'] as String?;

        if (_user?.uid != uid) {
          if (kDebugMode) debugPrint('⚠️ User changed, skipping language sync');
          return;
        }

        if (localLanguage != null && localLanguage != firestoreLanguage) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({'languageCode': localLanguage}).timeout(
                  const Duration(seconds: 5));

          if (kDebugMode) {
            debugPrint(
                '🌍 Synced language to Firestore: $firestoreLanguage → $localLanguage');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Failed to sync language: $e');
      }
    });
  }

  void _updateUserDataFromDoc(DocumentSnapshot doc) {
    // ✅ FIX: Skip updates during name save to prevent race conditions
    if (_isNameSaveInProgress) {
      if (kDebugMode)
        debugPrint('⏸️ Skipping data update - name save in progress');
      return;
    }

    final data = doc.data() as Map<String, dynamic>? ?? {};
    _isAdmin = data['isAdmin'] == true;
    _profileData = data;

    final isComplete = data['gender'] != null && data['birthDate'] != null;
    if (_profileComplete != isComplete) {
      _profileComplete = isComplete;
      _cacheProfileComplete(isComplete);
    }

    if (isAppleUser) {
      final displayName = data['displayName'] as String?;
      final email = data['email'] as String? ?? _user?.email ?? '';
      final emailPrefix = email.split('@').first;

      final hasValidName = displayName != null &&
          displayName.isNotEmpty &&
          displayName != 'User' &&
          displayName != 'No Name' &&
          displayName != emailPrefix;

      // ✅ FIX: Additional guard - don't override if already marked complete
      if (!_isNameSaveInProgress && _nameComplete != hasValidName) {
        // Only update to false if we're certain (server data says invalid)
        // Don't override true -> false during race conditions
        if (hasValidName || _nameComplete == null) {
          _nameComplete = hasValidName;
          _cacheNameComplete(hasValidName);
        }
      }
    }
  }

  Future<void> _createDefaultUserDoc() async {
    if (_user == null) return;

    try {
      if (kDebugMode) {
        debugPrint(
            'User document not found, setting safe defaults for ${_user!.uid}');
      }

      final prefs = await SharedPreferences.getInstance();
      final currentLocale = prefs.getString('locale') ?? 'tr';

      _profileData = {
        'displayName':
            _user!.displayName ?? _user!.email?.split('@')[0] ?? 'User',
        'email': _user!.email ?? '',
        'isAdmin': false,
        'isNew': true,
        'languageCode': currentLocale,
      };
      _isAdmin = false;
      _profileComplete ??= false;
    } catch (e) {
      if (kDebugMode) debugPrint('Error setting default user data: $e');
      _profileData = {
        'displayName': 'User',
        'email': _user!.email ?? '',
        'isAdmin': false,
        'isNew': true,
        'languageCode': 'tr',
      };
      _isAdmin = false;
      _profileComplete ??= false;
    }
  }

  Future<void> updateUserDataImmediately(User user,
      {bool? profileComplete}) async {
    _user = user;

    if (profileComplete != null && _profileComplete != profileComplete) {
      _profileComplete = profileComplete;
      _cacheProfileComplete(profileComplete);
    }

    notifyListeners();
    _backgroundFetchUserData();
  }

  void setProfileComplete(bool complete) {
    if (_profileComplete != complete) {
      _profileComplete = complete;
      _cacheProfileComplete(complete);
      notifyListeners();
    }
  }

  Future<void> _backgroundFetchUserData() async {
    // ✅ FIX: Skip background fetch during name save
    if (_isNameSaveInProgress) {
      if (kDebugMode)
        debugPrint('⏸️ Skipping background fetch - name save in progress');
      return;
    }

    final uid = _user?.uid;
    if (uid == null) return;

    // ✅ FIX: Debounce to prevent rapid consecutive fetches
    _backgroundFetchDebounce?.cancel();
    _backgroundFetchDebounce = Timer(_backgroundFetchDelay, () async {
      // Double-check save isn't in progress after delay
      if (_isNameSaveInProgress) return;

      await _executeBackgroundFetch(uid);
    });
  }

  Future<void> _executeBackgroundFetch(String uid) async {
    const maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      // ✅ FIX: Check save status before each retry
      if (_isNameSaveInProgress) {
        if (kDebugMode)
          debugPrint('⏸️ Aborting background fetch - name save started');
        return;
      }

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));

        if (_user == null || _user!.uid != uid || _isNameSaveInProgress) {
          if (kDebugMode)
            debugPrint(
                'User changed or save in progress, aborting background fetch');
          return;
        }

        if (doc.exists) {
          _updateUserDataFromDoc(doc);
          notifyListeners();
        }
        return;
      } catch (e) {
        retryCount++;
        if (kDebugMode)
          debugPrint('⚠️ Background fetch attempt $retryCount failed: $e');

        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 250 * (1 << retryCount)));

          if (_user == null || _user!.uid != uid || _isNameSaveInProgress) {
            if (kDebugMode)
              debugPrint(
                  'User changed or save in progress during retry delay, aborting');
            return;
          }
        } else {
          if (kDebugMode) {
            debugPrint(
                'Error in background fetch after $maxRetries attempts: $e');
          }
        }
      }
    }
  }

  Future<void> refreshUser() async {
    try {
      await _user?.reload();
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) {
        await fetchUserData();
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Error refreshing user: $e');
    }
  }

  Future<void> updateProfileData(Map<String, dynamic> updates) async {
    final uid = _user?.uid;
    if (uid == null) return;

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await docRef.get().timeout(const Duration(seconds: 10));

      final currentData = doc.data() ?? {};

      if (!updates.containsKey('languageCode') &&
          currentData.containsKey('languageCode')) {
        updates = {...updates, 'languageCode': currentData['languageCode']};
      }

      if (doc.exists) {
        await docRef.update(updates).timeout(const Duration(seconds: 10));
      } else {
        await docRef
            .set(updates, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      }

      if (_user?.uid != uid) return;

      _profileData = {...(_profileData ?? {}), ...updates};

      final isComplete =
          _profileData!['gender'] != null && _profileData!['birthDate'] != null;

      if (_profileComplete != isComplete) {
        _profileComplete = isComplete;
        _cacheProfileComplete(isComplete);
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating profile data: $e');
      rethrow;
    }
  }

  Future<void> updateLanguageCode(String languageCode) async {
    final uid = _user?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update(
          {'languageCode': languageCode}).timeout(const Duration(seconds: 10));

      if (_user?.uid != uid) return;

      _profileData = {...(_profileData ?? {}), 'languageCode': languageCode};
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating language code: $e');
      rethrow;
    }
  }

  Future<String?> getIdToken() async {
    if (_user == null) {
      if (kDebugMode) debugPrint('No user logged in to fetch ID token.');
      return null;
    }
    return await _user!.getIdToken(true);
  }

  Map<String, dynamic>? get profileData => _profileData;

  T? getProfileField<T>(String key) {
    return _profileData?[key] as T?;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _backgroundFetchDebounce?.cancel();
    super.dispose();
  }
}

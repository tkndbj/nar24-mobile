// lib/auth_service.dart
// Production-ready implementation for google_sign_in: ^7.2.0

import 'dart:async';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'services/personalized_feed_service.dart';
import 'widgets/preference_product.dart';
import 'widgets/terasmarket/teras_preference_product.dart';
import 'services/two_factor_service.dart';
import 'dart:math';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'utils/network_utils.dart';
import 'dart:convert' show base64, json, utf8;
import 'package:crypto/crypto.dart' as crypto;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final TwoFactorService _twoFactorService = TwoFactorService();

  /// Server Client ID for Google Sign-In (Web Client ID from Firebase Console)
  /// Required for Android with google_sign_in v7
  final String? _googleServerClientId;
  final String? _iosClientId;
  // Brute force protection
  final Map<String, int> _loginAttempts = {};
  final Map<String, DateTime> _lockoutUntil = {};
  static const int _maxLoginAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 15);

  // Background task queue
  final List<Future<void> Function()> _backgroundTasks = [];
  bool _isProcessingBackground = false;

  // Google Sign-In v7 state
  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;
  bool _isGoogleSignInInitialized = false;
  Completer<void>? _initCompleter;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventSubscription;
  StreamSubscription<String>? _fcmTokenSubscription;
  GoogleSignInAccount? _currentGoogleUser;

  // Dispose tracking
  bool _isDisposed = false;

  User? get currentUser => _auth.currentUser;
  bool get isGoogleSignedIn => _currentGoogleUser != null;
  GoogleSignInAccount? get currentGoogleUser => _currentGoogleUser;

  AuthService({
    String? googleServerClientId,
    String? iosClientId,
  })  : _googleServerClientId = googleServerClientId,
        _iosClientId = iosClientId {
    _initializeGoogleSignIn();
  }

  Future<void> _initializeGoogleSignIn() async {
    if (_isDisposed) return;
    if (_isGoogleSignInInitialized) {
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
      return;
    }

    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();

    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isDisposed) {
        _initCompleter?.completeError(
            StateError('AuthService disposed during initialization'));
        return;
      }

      try {
        if (Platform.isIOS) {
          // ✅ iOS: Don't pass clientId - let it read from GIDClientID in Info.plist
          // Only pass serverClientId if needed for backend auth
          await GoogleSignIn.instance.initialize(
            serverClientId: _googleServerClientId,
          );
        } else if (Platform.isAndroid) {
          // Android: serverClientId is required (must be Web Client ID)
          await GoogleSignIn.instance.initialize(
            serverClientId: _googleServerClientId,
          );
        } else {
          throw UnsupportedError(
            'Google Sign-In is not supported on this platform.',
          );
        }

        // Subscribe to authentication events
        _authEventSubscription?.cancel();
        _authEventSubscription =
            GoogleSignIn.instance.authenticationEvents.listen(
          _handleGoogleAuthEvent,
          onError: _handleGoogleAuthError,
          cancelOnError: false,
        );

        _isGoogleSignInInitialized = true;
        _initCompleter?.complete();

        if (kDebugMode)
          debugPrint('✅ Google Sign-In v7 initialized (attempt $attempt)');
        return;
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint(
              '❌ Google Sign-In initialization attempt $attempt failed: $e');
        }

        final isLastAttempt = attempt == maxRetries;

        if (isLastAttempt) {
          _initCompleter?.completeError(e, stackTrace);
          _initCompleter = null;

          if (!kDebugMode) {
            FirebaseCrashlytics.instance.recordError(
              e,
              stackTrace,
              reason:
                  'Google Sign-In initialization failed after $maxRetries attempts',
            );
          }
          return;
        }

        await Future.delayed(retryDelay * attempt);
      }
    }
  }

  /// Ensures Google Sign-In is initialized before use
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_isDisposed) {
      throw StateError('AuthService has been disposed');
    }

    if (_isGoogleSignInInitialized) return;

    // If initialization failed previously, retry
    if (_initCompleter == null) {
      await _initializeGoogleSignIn();
    }

    await _initCompleter?.future;

    if (!_isGoogleSignInInitialized) {
      throw FirebaseAuthException(
        code: 'google-signin-init-failed',
        message: 'Failed to initialize Google Sign-In. Please try again.',
      );
    }
  }

  void _handleGoogleAuthEvent(GoogleSignInAuthenticationEvent event) {
    if (_isDisposed) return;

    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _currentGoogleUser = event.user;
        if (kDebugMode)
          debugPrint('Google user signed in: ${event.user.email}');
        break;
      case GoogleSignInAuthenticationEventSignOut():
        _currentGoogleUser = null;
        if (kDebugMode) debugPrint('Google user signed out');
        break;
    }
  }

  void _handleGoogleAuthError(Object error) {
    if (_isDisposed) return;

    if (kDebugMode) {
      if (error is GoogleSignInException) {
        debugPrint('Google Sign-In error: ${error.code}');
      } else {
        debugPrint('Google Sign-In error: $error');
      }
    }
  }

  /// Dispose all resources
  /// Call this when the service is no longer needed
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _authEventSubscription?.cancel();
    _authEventSubscription = null;

    _fcmTokenSubscription?.cancel();
    _fcmTokenSubscription = null;

    _backgroundTasks.clear();
    _currentGoogleUser = null;

    if (kDebugMode) debugPrint('AuthService disposed');
  }

  // ============================================================
  // BACKGROUND TASK PROCESSING
  // ============================================================

  Future<void> _processBackgroundTasks() async {
    if (_isDisposed || _isProcessingBackground || _backgroundTasks.isEmpty) {
      return;
    }

    _isProcessingBackground = true;

    while (_backgroundTasks.isNotEmpty && !_isDisposed) {
      final task = _backgroundTasks.removeAt(0);
      try {
        await task();
      } catch (e) {
        if (kDebugMode) debugPrint('Background task failed: $e');
      }

      if (_backgroundTasks.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _isProcessingBackground = false;
  }

  void _queueBackgroundTask(Future<void> Function() task) {
    if (_isDisposed) return;
    _backgroundTasks.add(task);
    _processBackgroundTasks();
  }

  // ============================================================
  // FCM TOKEN MANAGEMENT
  // ============================================================

  Future<void> _handleTokenRefresh(String newToken) async {
    final user = _auth.currentUser;
    if (user == null || _isDisposed) return;

    _queueBackgroundTask(() => _registerFcmToken(user.uid, newToken));
  }

  Future<String> _getDeviceIdentifier() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final deviceId = androidInfo.id;
        if (deviceId.isNotEmpty && !deviceId.contains('.')) {
          return deviceId;
        }
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final iosId = iosInfo.identifierForVendor;
        if (iosId != null && iosId.isNotEmpty) {
          return iosId;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Device ID retrieval failed: $e');
    }

    // Fallback to stored or generated ID
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');

    if (deviceId == null || deviceId.isEmpty) {
      deviceId =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }

  Future<void> _registerFcmToken(String userId, [String? providedToken]) async {
    const maxRetries = 3;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isDisposed) return;

      try {
        final token =
            providedToken ?? await FirebaseMessaging.instance.getToken();
        if (token == null || token.isEmpty) return;

        final deviceId = await _getDeviceIdentifier();
        final platform = Platform.isIOS ? 'ios' : 'android';

        // Store locally first
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
        await prefs.setString('fcm_device_id', deviceId);
        await prefs.setBool('fcm_needs_sync', true);

        // Sync to server
        final callable = _functions.httpsCallable('registerFcmToken');
        await callable.call({
          'token': token,
          'deviceId': deviceId,
          'platform': platform,
        }).timeout(const Duration(seconds: 5));

        await prefs.setBool('fcm_needs_sync', false);
        if (kDebugMode) debugPrint('FCM token registered');
        return;
      } catch (e) {
        if (kDebugMode)
          debugPrint('FCM registration attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
  }

  Future<void> _removeFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('fcm_token');
      final deviceId =
          prefs.getString('fcm_device_id') ?? await _getDeviceIdentifier();

      // Clear local data first
      await prefs.remove('fcm_token');
      await prefs.remove('fcm_needs_sync');

      // Delete local FCM token
      await FirebaseMessaging.instance.deleteToken();

      // Remove from server
      if (token != null || deviceId.isNotEmpty) {
        final callable = _functions.httpsCallable('removeFcmToken');
        await callable.call({
          'token': token,
          'deviceId': deviceId,
        }).timeout(const Duration(seconds: 5));
      }

      if (kDebugMode) debugPrint('FCM token removed');
    } catch (e) {
      if (kDebugMode) debugPrint('FCM token removal error: $e');
    }
  }

  /// Manually sync FCM token if needed
  Future<void> ensureFcmRegistered() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('fcm_needs_sync') ?? true) {
      await _registerFcmToken(user.uid);
    }
  }

  // ============================================================
  // BRUTE FORCE PROTECTION
  // ============================================================

  void _checkAccountLockout(String email) {
    final lockoutEnd = _lockoutUntil[email];
    if (lockoutEnd != null && lockoutEnd.isAfter(DateTime.now())) {
      final remainingMinutes =
          lockoutEnd.difference(DateTime.now()).inMinutes + 1;
      throw FirebaseAuthException(
        code: 'too-many-attempts',
        message: 'Account locked. Try again in $remainingMinutes minutes.',
      );
    }
  }

  void _recordFailedAttempt(String email) {
    final attempts = (_loginAttempts[email] ?? 0) + 1;
    _loginAttempts[email] = attempts;

    if (attempts >= _maxLoginAttempts) {
      _lockoutUntil[email] = DateTime.now().add(_lockoutDuration);
      _loginAttempts.remove(email);
    }
  }

  void _clearFailedAttempts(String email) {
    _loginAttempts.remove(email);
    _lockoutUntil.remove(email);
  }

  // ============================================================
  // EMAIL/PASSWORD AUTHENTICATION
  // ============================================================

  Future<Map<String, dynamic>> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final normalizedEmail = email.trim().toLowerCase();
    _checkAccountLockout(normalizedEmail);

    try {
      // Wrap Firebase auth call with retry and timeout for network resilience
      final cred = await NetworkUtils.executeAuthOperation(
        () => _auth.signInWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
        ),
      );

      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'Sign-in failed. Please try again.',
        );
      }

      _clearFailedAttempts(normalizedEmail);

      // Check email verification
      if (!user.emailVerified) {
        final isPasswordUser = user.providerData.any(
          (info) => info.providerId == 'password',
        );
        if (isPasswordUser) {
          throw FirebaseAuthException(
            code: 'email-not-verified',
            message: 'Please verify your email before signing in.',
          );
        }
      }

      // Parallel checks for profile and 2FA
      final results = await Future.wait([
        _checkProfileCompletion(user),
        _twoFactorService.is2FAEnabled(),
      ]);

      final needsCompletion =
          (results[0] as Map<String, dynamic>)['needsCompletion'] as bool;
      final needs2FA = results[1] as bool;

      // Background FCM registration
      _queueBackgroundTask(() => _registerFcmToken(user.uid));

      return {
        'user': user,
        'needs2FA': needs2FA,
        'needsCompletion': needsCompletion,
      };
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential') {
        _recordFailedAttempt(normalizedEmail);
      }
      rethrow;
    }
  }

  Future<User?> registerWithEmailAndPassword(
    String email,
    String password,
    String name,
    String surname, {
    String? gender,
    DateTime? birthDate,
    String? referralCode,
    String? languageCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final callable = _functions.httpsCallable('registerWithEmailPassword');
      final result = await callable.call(<String, dynamic>{
        'email': normalizedEmail,
        'password': password,
        'name': name.trim(),
        'surname': surname.trim(),
        if (gender != null) 'gender': gender,
        if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
        if (referralCode != null && referralCode.isNotEmpty)
          'referralCode': referralCode.trim(),
        if (languageCode != null && languageCode.isNotEmpty)
          'languageCode': languageCode,
      });

      final customToken = result.data['customToken'] as String;
      final cred = await _auth.signInWithCustomToken(customToken);

      if (cred.user != null) {
        _queueBackgroundTask(() => _registerFcmToken(cred.user!.uid));
      }

      return cred.user;
    } on FirebaseFunctionsException catch (e) {
      throw FirebaseAuthException(
        code: 'registration-failed',
        message: e.message ?? 'Registration failed. Please try again.',
      );
    }
  }

  // ============================================================
  // GOOGLE SIGN-IN (v7)
  // ============================================================

  Future<Map<String, dynamic>> signInWithGoogle(
      {bool forceAccountPicker = false}) async {
    try {
      await _ensureGoogleSignInInitialized();

      GoogleSignInAccount? googleUser;

      // Always disconnect first when forcing account picker
      if (forceAccountPicker) {
        try {
          await _googleSignIn.disconnect();
          _currentGoogleUser = null;
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          if (kDebugMode) debugPrint('Pre-auth disconnect: $e');
        }
      } else {
        final Future<GoogleSignInAccount?>? lightweightFuture =
            _googleSignIn.attemptLightweightAuthentication();

        if (lightweightFuture != null) {
          googleUser = await lightweightFuture;
        }
      }

      // Authenticate if needed
      if (googleUser == null) {
        if (!_googleSignIn.supportsAuthenticate()) {
          throw FirebaseAuthException(
            code: 'google-signin-unsupported',
            message: 'Google Sign-In is not supported on this platform.',
          );
        }

        googleUser = await _googleSignIn.authenticate();
      }

      if (kDebugMode) {
        debugPrint('========== GOOGLE SIGN-IN DEBUG ==========');
        debugPrint('User email: ${googleUser.email}');
        debugPrint('User ID: ${googleUser.id}');
      }

      // Get token
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (kDebugMode) {
        debugPrint('ID Token present: ${idToken != null}');
        debugPrint('ID Token length: ${idToken?.length ?? 0}');

        // Decode and check token claims
        if (idToken != null) {
          try {
            final parts = idToken.split('.');
            if (parts.length == 3) {
              final payload = parts[1];
              final normalized = base64.normalize(payload);
              final decoded = utf8.decode(base64.decode(normalized));
              final claims = json.decode(decoded) as Map<String, dynamic>;

              final iat = claims['iat'] as int?;
              final exp = claims['exp'] as int?;
              final aud = claims['aud'];

              if (iat != null) {
                final issuedAt =
                    DateTime.fromMillisecondsSinceEpoch(iat * 1000);
                debugPrint('Token issued at: $issuedAt');
                debugPrint('Current time: ${DateTime.now()}');
                debugPrint(
                    'Token age: ${DateTime.now().difference(issuedAt).inSeconds} seconds');
              }
              if (exp != null) {
                final expiresAt =
                    DateTime.fromMillisecondsSinceEpoch(exp * 1000);
                debugPrint('Token expires at: $expiresAt');
              }
              debugPrint('Token audience (aud): $aud');
            }
          } catch (e) {
            debugPrint('Error decoding token: $e');
          }
        }
        debugPrint('==========================================');
      }

      if (idToken == null || idToken.isEmpty) {
        await _googleSignIn.disconnect();
        _currentGoogleUser = null;
        throw FirebaseAuthException(
          code: 'google-token-failed',
          message: 'Failed to obtain authentication token. Please try again.',
        );
      }

      // Sign in to Firebase
      final credential = GoogleAuthProvider.credential(idToken: idToken);

      final UserCredential firebaseCred;
      try {
        firebaseCred = await _auth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (kDebugMode) {
          debugPrint('========== FIREBASE ERROR ==========');
          debugPrint('Error code: ${e.code}');
          debugPrint('Error message: ${e.message}');
          debugPrint('=====================================');
        }

        // Clean up and let user retry manually
        await _googleSignIn.disconnect();
        _currentGoogleUser = null;

        throw FirebaseAuthException(
          code: 'google-signin-failed',
          message: 'Authentication failed. Please try again.',
        );
      }

      final User? user = firebaseCred.user;

      if (user == null) {
        return {
          'user': null,
          'isNewUser': false,
          'needsCompletion': false,
          'needs2FA': false,
        };
      }

      final isNewUser = firebaseCred.additionalUserInfo?.isNewUser ?? false;

      if (isNewUser) {
        await _createUserDocument(user);
        _queueBackgroundTask(() => _registerFcmToken(user.uid));

        return {
          'user': user,
          'isNewUser': true,
          'needsCompletion': true,
          'needs2FA': false,
        };
      }

      final results = await Future.wait([
        _checkProfileCompletion(user),
        _twoFactorService.is2FAEnabled(),
      ]);

      final needsCompletion =
          (results[0] as Map<String, dynamic>)['needsCompletion'] as bool;
      final needs2FA = results[1] as bool;

      _queueBackgroundTask(() => _registerFcmToken(user.uid));

      return {
        'user': user,
        'isNewUser': false,
        'needsCompletion': needsCompletion,
        'needs2FA': needs2FA,
      };
    } on GoogleSignInException catch (e) {
      if (kDebugMode) debugPrint('Google Sign-In exception: ${e.code}');

      final String message = switch (e.code) {
        GoogleSignInExceptionCode.canceled => 'Sign-in was cancelled.',
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google Sign-In configuration error. Please contact support.',
        GoogleSignInExceptionCode.unknownError =>
          e.description ?? 'An unexpected error occurred. Please try again.',
        GoogleSignInExceptionCode() =>
          'Google sign-in failed. Please try again.',
      };

      throw FirebaseAuthException(
        code: 'google-signin-failed',
        message: message,
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('Google Sign-In error: $e');
      throw FirebaseAuthException(
        code: 'google-signin-failed',
        message: 'Google sign-in failed. Please try again.',
      );
    }
  }

  /// Attempt silent Google sign-in
  Future<GoogleSignInAccount?> attemptSilentGoogleSignIn() async {
    try {
      await _ensureGoogleSignInInitialized();

      final Future<GoogleSignInAccount?>? result =
          _googleSignIn.attemptLightweightAuthentication();

      if (result != null) {
        return await result;
      }
      return _currentGoogleUser;
    } catch (e) {
      if (kDebugMode) debugPrint('Silent Google sign-in failed: $e');
      return null;
    }
  }

  // ============================================================
  // APPLE SIGN-IN
  // ============================================================

  /// Sign in with Apple (iOS only)
  Future<Map<String, dynamic>> signInWithApple() async {
    if (!Platform.isIOS) {
      throw FirebaseAuthException(
        code: 'apple-signin-unsupported',
        message: 'Apple Sign-In is only available on iOS devices.',
      );
    }

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (appleCredential.identityToken == null) {
        throw FirebaseAuthException(
          code: 'apple-signin-failed',
          message: 'Apple did not return an identity token.',
        );
      }

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // ✅ Firebase auth - this is what matters
      final firebaseCred = await _auth.signInWithCredential(oauthCredential);
      final User? user = firebaseCred.user;

      if (user == null) {
        return {
          'user': null,
          'isNewUser': false,
          'needsCompletion': false,
          'needsName': false,
          'needs2FA': false,
        };
      }

      final isNewUser = firebaseCred.additionalUserInfo?.isNewUser ?? false;

      // Capture Apple's data
      String? displayName;
      String? email = appleCredential.email ?? user.email;

      if (appleCredential.givenName != null ||
          appleCredential.familyName != null) {
        displayName = [
          appleCredential.givenName,
          appleCredential.familyName,
        ].where((e) => e != null && e.isNotEmpty).join(' ');
      }

      // ⚠️ WRAP ALL POST-AUTH OPERATIONS IN TRY-CATCH
      // So they don't cause "sign-in failed" even though user IS signed in

      try {
        if (displayName != null && displayName.isNotEmpty) {
          await user.updateDisplayName(displayName);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to update displayName: $e');
      }

      bool needsCompletion = true;
      bool needsName = displayName == null || displayName.isEmpty;

      if (isNewUser) {
        try {
          await _createUserDocument(user,
              displayName: displayName, email: email);
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to create user document: $e');
        }

        _queueBackgroundTask(() => _registerFcmToken(user.uid));

        final hasValidName = displayName != null &&
            displayName.isNotEmpty &&
            !displayName.contains('@'); // Not an email

        return {
          'user': user,
          'isNewUser': true,
          'needsCompletion': true,
          'needsName': !hasValidName,
          'needs2FA': false,
        };
      }

      // Existing user - wrap in try-catch
      try {
        if (displayName != null && displayName.isNotEmpty) {
          await _updateUserDisplayNameIfMissing(user.uid, displayName, email);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to update user displayName: $e');
      }

      try {
        final profileCheck = await _checkProfileCompletionWithName(user);
        needsCompletion = profileCheck['needsCompletion'] as bool;
        needsName = profileCheck['needsName'] as bool;
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to check profile: $e');
        needsCompletion = true;
        needsName = true;
      }

      bool needs2FA = false;
      try {
        needs2FA = await _twoFactorService.is2FAEnabled();
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to check 2FA: $e');
      }

      _queueBackgroundTask(() => _registerFcmToken(user.uid));

      return {
        'user': user,
        'isNewUser': false,
        'needsCompletion': needsCompletion,
        'needsName': needsName,
        'needs2FA': needs2FA,
      };
    } on SignInWithAppleAuthorizationException catch (e) {
      if (kDebugMode) debugPrint('Apple Sign-In exception: ${e.code}');

      final String message = switch (e.code) {
        AuthorizationErrorCode.canceled => 'Sign-in was cancelled.',
        AuthorizationErrorCode.failed =>
          'Apple Sign-In failed. Please try again.',
        AuthorizationErrorCode.invalidResponse =>
          'Invalid response from Apple. Please try again.',
        AuthorizationErrorCode.notHandled =>
          'Apple Sign-In was not handled. Please try again.',
        AuthorizationErrorCode.notInteractive =>
          'Apple Sign-In requires user interaction.',
        AuthorizationErrorCode.unknown =>
          'An unexpected error occurred. Please try again.',
        _ => 'An unexpected error occurred. Please try again.',
      };

      throw FirebaseAuthException(
        code: 'apple-signin-failed',
        message: message,
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('Apple Sign-In error: $e');
      throw FirebaseAuthException(
        code: 'apple-signin-failed',
        message: 'Apple sign-in failed. Please try again.',
      );
    }
  }

  Future<void> _updateUserDisplayNameIfMissing(
      String uid, String displayName, String? email) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final updates = <String, dynamic>{};

        // Update displayName if missing or placeholder
        if (data['displayName'] == null ||
            data['displayName'] == 'User' ||
            data['displayName'] == 'No Name' ||
            (data['displayName'] as String).isEmpty) {
          updates['displayName'] = displayName;
        }

        // Update email if missing
        if (email != null &&
            email.isNotEmpty &&
            (data['email'] == null || (data['email'] as String).isEmpty)) {
          updates['email'] = email;
        }

        if (updates.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update(updates);
          if (kDebugMode) debugPrint('Updated user displayName/email for $uid');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error updating user displayName: $e');
    }
  }

  /// Check profile completion including name check
  Future<Map<String, dynamic>> _checkProfileCompletionWithName(
      User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};

      final displayName = data['displayName'] as String?;
      final email = data['email'] as String? ?? user.email ?? '';
      final emailPrefix = email.split('@').first;

      // ✅ FIX: Also check if name is just the email prefix
      final needsName = displayName == null ||
          displayName.isEmpty ||
          displayName == 'User' ||
          displayName == 'No Name' ||
          displayName == emailPrefix; // ← ADD THIS

      final needsCompletion = data['gender'] == null ||
          data['birthDate'] == null ||
          data['languageCode'] == null;

      return {
        'needsCompletion': needsCompletion,
        'needsName': needsName,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Profile check failed: $e');
      return {
        'needsCompletion': true,
        'needsName': true,
      };
    }
  }

  // ============================================================
  // PROFILE MANAGEMENT
  // ============================================================

  Future<Map<String, dynamic>> _checkProfileCompletion(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};

      final needsCompletion = data['gender'] == null ||
          data['birthDate'] == null ||
          data['languageCode'] == null;

      return {'needsCompletion': needsCompletion};
    } catch (e) {
      if (kDebugMode) debugPrint('Profile check failed: $e');
      return {'needsCompletion': true};
    }
  }

  Future<String> _getCurrentLanguageCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('locale') ?? 'tr';
    } catch (e) {
      return 'tr';
    }
  }

  Future<void> _createUserDocument(User user,
      {String? displayName, String? email}) async {
    const maxRetries = 3;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final docRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        final existingDoc = await docRef.get();
        final existingData = existingDoc.data();

        final languageCode =
            existingData?['languageCode'] ?? await _getCurrentLanguageCode();

        // ✅ FIX: Don't fallback to email prefix - use placeholder instead
        String? finalDisplayName = displayName;
        if (finalDisplayName == null || finalDisplayName.isEmpty) {
          finalDisplayName = user.displayName;
        }
        // Don't use email as name - leave as null or 'User'
        if (finalDisplayName == null ||
            finalDisplayName.isEmpty ||
            finalDisplayName.contains('@')) {
          finalDisplayName = null; // Will trigger name completion screen
        }

        await docRef.set({
          'displayName': finalDisplayName, // Can be null
          'email': email ?? user.email ?? '',
          'isNew': true,
          'createdAt': FieldValue.serverTimestamp(),
          'emailVerifiedAt':
              user.emailVerified ? FieldValue.serverTimestamp() : null,
          'languageCode': languageCode,
        }, SetOptions(merge: true));

        // Verify creation
        final verifyDoc = await docRef.get();
        if (verifyDoc.exists) {
          if (kDebugMode) debugPrint('User document created for ${user.uid}');
          return;
        }

        throw Exception('Document verification failed');
      } catch (e) {
        if (kDebugMode)
          debugPrint('User document creation attempt $attempt failed: $e');

        if (attempt >= maxRetries) {
          rethrow;
        }

        await Future.delayed(Duration(milliseconds: 250 * (1 << attempt)));
      }
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    try {
      final userId = _auth.currentUser?.uid;

      // Step 1: Run FCM removal and Google disconnect in parallel (independent operations)
      await Future.wait([
        // FCM token removal with timeout
        if (userId != null)
          _removeFcmToken().timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              if (kDebugMode) debugPrint('FCM removal timed out');
            },
          ),
        // Google disconnect with timeout
        _disconnectGoogleWithTimeout(),
      ], eagerError: false);

      // Step 2: Sign out from Firebase (must happen after Google disconnect)
      await _auth.signOut();

      // Step 3: Clear local data and caches in parallel
      final prefs = await SharedPreferences.getInstance();

      // Preserve agreement acceptance keys (they're user-specific and should persist)
      final agreementKeys = prefs
          .getKeys()
          .where((k) => k.startsWith('agreements_accepted_'))
          .toList();
      final preservedAgreements = <String, bool>{};
      for (final key in agreementKeys) {
        preservedAgreements[key] = prefs.getBool(key) ?? false;
      }

      await Future.wait([
        prefs.clear(),
        PersonalizedFeedService.instance.clearCache(),
      ], eagerError: false);

      // Restore agreement acceptance keys
      for (final entry in preservedAgreements.entries) {
        await prefs.setBool(entry.key, entry.value);
      }

      // Sync cache clears (fast, no await needed)
      PreferenceProduct.clearCache();
      TerasPreferenceProduct.clearCache();

      if (kDebugMode) debugPrint('User logged out successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('Logout error: $e');
      // Ensure Firebase sign out happens even if other cleanup fails
      try {
        await _auth.signOut();
      } catch (_) {}
    }
  }

  /// Helper to disconnect from Google with timeout
  Future<void> _disconnectGoogleWithTimeout() async {
    try {
      await _ensureGoogleSignInInitialized();
      await _googleSignIn.disconnect().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) debugPrint('Google disconnect timed out');
        },
      );
      _currentGoogleUser = null;
    } catch (e) {
      if (kDebugMode) debugPrint('Google disconnect error: $e');
      // Clear local state even if disconnect fails
      _currentGoogleUser = null;
    }
  }

  /// Sign out from Google only (lighter, keeps some cached data)
  Future<void> signOutFromGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
      await _googleSignIn.signOut();
      _currentGoogleUser = null;
    } catch (e) {
      if (kDebugMode) debugPrint('Google sign-out error: $e');
    }
  }

  /// Disconnect from Google completely (revokes access)
  Future<void> disconnectFromGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
      await _googleSignIn.disconnect();
      _currentGoogleUser = null;
    } catch (e) {
      if (kDebugMode) debugPrint('Google disconnect error: $e');
    }
  }

  // ============================================================
  // TOKEN & AUTHORIZATION UTILITIES
  // ============================================================

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _auth.currentUser?.getIdToken(forceRefresh);
  }

  /// Get fresh Google ID token
  Future<String?> getFreshGoogleIdToken() async {
    try {
      await _ensureGoogleSignInInitialized();

      final googleUser = _currentGoogleUser;
      if (googleUser == null) return null;

      final auth = await googleUser.authentication;
      return auth.idToken;
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting Google ID token: $e');
      return null;
    }
  }

  /// Request additional Google API scopes
  Future<bool> requestGoogleScopes(List<String> scopes) async {
    try {
      await _ensureGoogleSignInInitialized();

      final googleUser = _currentGoogleUser;
      if (googleUser == null) return false;

      await googleUser.authorizationClient.authorizeScopes(scopes);
      return true;
    } on GoogleSignInException catch (e) {
      if (kDebugMode) debugPrint('Scope authorization failed: ${e.code}');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('Scope authorization error: $e');
      return false;
    }
  }

  /// Check if specific scopes are authorized
  Future<bool> hasGoogleScopes(List<String> scopes) async {
    try {
      await _ensureGoogleSignInInitialized();

      final googleUser = _currentGoogleUser;
      if (googleUser == null) return false;

      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(scopes);
      return authorization != null;
    } catch (e) {
      if (kDebugMode) debugPrint('Scope check error: $e');
      return false;
    }
  }

  /// Get authorization headers for Google API requests
  Future<Map<String, String>?> getGoogleAuthHeaders(List<String> scopes) async {
    try {
      await _ensureGoogleSignInInitialized();

      final googleUser = _currentGoogleUser;
      if (googleUser == null) return null;

      return await googleUser.authorizationClient.authorizationHeaders(scopes);
    } catch (e) {
      if (kDebugMode) debugPrint('Auth headers error: $e');
      return null;
    }
  }

  /// Get server auth code for backend verification
  Future<String?> getGoogleServerAuthCode(List<String> scopes) async {
    try {
      await _ensureGoogleSignInInitialized();

      final googleUser = _currentGoogleUser;
      if (googleUser == null) return null;

      final serverAuth =
          await googleUser.authorizationClient.authorizeServer(scopes);
      return serverAuth?.serverAuthCode;
    } catch (e) {
      if (kDebugMode) debugPrint('Server auth code error: $e');
      return null;
    }
  }
}

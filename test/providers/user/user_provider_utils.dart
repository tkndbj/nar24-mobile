// test/utils/user_provider_utils.dart
//
// EXTRACTED PURE LOGIC from UserProvider
// These functions are EXACT COPIES of logic from the UserProvider,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with lib/user_provider.dart

/// Profile completion check - EXACT logic from UserProvider
class UserProviderUtils {
  // ============================================================================
  // PROFILE COMPLETION LOGIC
  // ============================================================================

  /// Check if profile is complete based on cached value and profile data
  /// This is the EXACT logic from UserProvider.isProfileComplete getter
  static bool isProfileComplete({
    bool? cachedProfileComplete,
    Map<String, dynamic>? profileData,
  }) {
    // Use cached value if explicitly set (e.g., during login flow or from SharedPreferences)
    // This prevents race condition where _profileData hasn't loaded yet
    if (cachedProfileComplete != null) return cachedProfileComplete;

    // Fall back to deriving from profile data fields
    if (profileData == null) return false;

    return profileData['gender'] != null &&
        profileData['birthDate'] != null &&
        profileData['languageCode'] != null;
  }

  /// Check if profile state is ready (determined from cache or Firestore)
  /// EXACT logic from UserProvider.isProfileStateReady getter
  static bool isProfileStateReady({
    bool? cachedProfileComplete,
    Map<String, dynamic>? profileData,
  }) {
    return cachedProfileComplete != null || profileData != null;
  }

  // ============================================================================
  // PROFILE DATA EXTRACTION
  // ============================================================================

  /// Extract profile completion status from Firestore document data
  /// EXACT logic from UserProvider._updateUserDataFromDoc
  static bool extractProfileCompleteFromData(Map<String, dynamic>? data) {
    if (data == null) return false;

    return data['gender'] != null &&
        data['birthDate'] != null &&
        data['languageCode'] != null;
  }

  /// Extract isAdmin from document data
  static bool extractIsAdminFromData(Map<String, dynamic>? data) {
    if (data == null) return false;
    return data['isAdmin'] == true;
  }

  /// Check if cached value should be updated
  static bool shouldUpdateCache(bool? currentCached, bool newValue) {
    return currentCached != newValue;
  }

  // ============================================================================
  // GOOGLE USER CHECK
  // ============================================================================

  /// Check if user logged in with Google
  /// Simulates the logic from UserProvider.isGoogleUser
  static bool isGoogleUser(List<String> providerIds) {
    return providerIds.contains('google.com');
  }

  // ============================================================================
  // DEFAULT USER DOC
  // ============================================================================

  /// Build default user document for new users
  /// EXACT logic from UserProvider._createDefaultUserDoc
  static Map<String, dynamic> buildDefaultUserDoc({
    String? displayName,
    String? email,
    String languageCode = 'tr',
  }) {
    return {
      'displayName': displayName ?? email?.split('@')[0] ?? 'User',
      'email': email ?? '',
      'isAdmin': false,
      'isNew': true,
      'languageCode': languageCode,
    };
  }

  /// Extract display name with fallback
  static String extractDisplayName({
    String? displayName,
    String? email,
  }) {
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    if (email != null && email.contains('@')) {
      return email.split('@')[0];
    }
    return 'User';
  }

  // ============================================================================
  // PROFILE UPDATE LOGIC
  // ============================================================================

  /// Merge profile updates while preserving languageCode
  /// EXACT logic from UserProvider.updateProfileData
  static Map<String, dynamic> mergeProfileUpdates({
    required Map<String, dynamic> currentData,
    required Map<String, dynamic> updates,
  }) {
    // Preserve languageCode if not explicitly updating it
    if (!updates.containsKey('languageCode') &&
        currentData.containsKey('languageCode')) {
      return {...updates, 'languageCode': currentData['languageCode']};
    }
    return updates;
  }

  /// Check profile completion after updates
  static bool checkProfileCompleteAfterUpdate(Map<String, dynamic> mergedData) {
    return mergedData['gender'] != null &&
        mergedData['birthDate'] != null &&
        mergedData['languageCode'] != null;
  }

  // ============================================================================
  // RETRY LOGIC
  // ============================================================================

  /// Calculate retry delay with exponential backoff
  /// EXACT logic from UserProvider.fetchUserData retry
  static Duration calculateRetryDelay(int retryCount) {
    // 250 * (1 << retryCount) = 250 * 2^retryCount
    // retryCount 1 -> 500ms
    // retryCount 2 -> 1000ms
    // retryCount 3 -> 2000ms
    return Duration(milliseconds: 250 * (1 << retryCount));
  }

  /// Check if should retry
  static bool shouldRetry(int currentAttempt, int maxRetries) {
    return currentAttempt < maxRetries;
  }

  // ============================================================================
  // STATE RESET LOGIC
  // ============================================================================

  /// Get reset state values (used during logout)
  static Map<String, dynamic> getResetState() {
    return {
      'isAdmin': false,
      'profileData': null,
      'profileComplete': null,
      'isLoading': false,
    };
  }

  // ============================================================================
  // LIFECYCLE / RESUME LOGIC
  // ============================================================================

  /// Check if should do full refresh based on pause duration
  /// Uses LifecycleAwareMixin.shouldFullRefresh logic (default 5 min threshold)
  static bool shouldFullRefresh(Duration pauseDuration, {Duration? threshold}) {
    final refreshThreshold = threshold ?? const Duration(minutes: 5);
    return pauseDuration > refreshThreshold;
  }

  // ============================================================================
  // AUTH STATE LOGIC
  // ============================================================================

  /// Determine if this is a login event (was logged out, now logged in)
  static bool isLoginEvent({
    required bool hadUserBefore,
    required bool hasUserNow,
  }) {
    return !hadUserBefore && hasUserNow;
  }

  /// Determine if this is a logout event
  static bool isLogoutEvent({
    required bool hadUserBefore,
    required bool hasUserNow,
  }) {
    return hadUserBefore && !hasUserNow;
  }

  /// Check if user ID changed (different user logged in)
  static bool didUserChange({
    String? previousUid,
    String? currentUid,
  }) {
    if (previousUid == null && currentUid == null) return false;
    return previousUid != currentUid;
  }

  // ============================================================================
  // CACHE VALIDATION
  // ============================================================================

  /// Validate cached profile state against actual data
  /// Returns true if cache is valid, false if corrupted
  static bool validateCacheAgainstData({
    required bool? cachedValue,
    required Map<String, dynamic>? profileData,
  }) {
    // If no cache, it's valid (just empty)
    if (cachedValue == null) return true;

    // If no profile data, can't validate - assume cache is stale
    if (profileData == null) return false;

    // Check if cache matches actual data
    final actualComplete = extractProfileCompleteFromData(profileData);
    return cachedValue == actualComplete;
  }

  /// Determine if cache should be cleared (corruption detected)
  static bool shouldClearCache({
    required bool? cachedValue,
    required Map<String, dynamic>? profileData,
    required bool hasUser,
  }) {
    // If no user, cache should be cleared
    if (!hasUser) return true;

    // If cache exists but doesn't match data, it's corrupted
    if (cachedValue != null && profileData != null) {
      return !validateCacheAgainstData(
        cachedValue: cachedValue,
        profileData: profileData,
      );
    }

    return false;
  }
}
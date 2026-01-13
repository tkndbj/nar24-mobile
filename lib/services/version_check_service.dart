// lib/services/version_check_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents the different app states based on version and maintenance status
enum AppUpdateState {
  /// App is up to date, no action needed
  upToDate,

  /// A new version is available but update is optional
  softUpdate,

  /// A new version is required, user must update to continue
  forceUpdate,

  /// App is under maintenance, all features disabled
  maintenance,
}

/// Holds all version check related data
class VersionCheckResult {
  final AppUpdateState state;
  final String currentVersion;
  final String latestVersion;
  final String? updateMessage;
  final String? maintenanceMessage;
  final DateTime? maintenanceEndTime;
  final String? storeUrl;
  final List<String> releaseNotes;

  const VersionCheckResult({
    required this.state,
    required this.currentVersion,
    required this.latestVersion,
    this.updateMessage,
    this.maintenanceMessage,
    this.maintenanceEndTime,
    this.storeUrl,
    this.releaseNotes = const [],
  });

  bool get requiresAction => state != AppUpdateState.upToDate;

  bool get isBlocking =>
      state == AppUpdateState.forceUpdate ||
      state == AppUpdateState.maintenance;

  @override
  String toString() {
    return 'VersionCheckResult(state: $state, current: $currentVersion, latest: $latestVersion)';
  }
}

/// Remote Config keys - centralized for easy maintenance
class _RemoteConfigKeys {
  static const String maintenanceMode = 'maintenance_mode';
  static const String maintenanceMessageEn = 'maintenance_message_en';
  static const String maintenanceMessageTr = 'maintenance_message_tr';
  static const String maintenanceMessageRu = 'maintenance_message_ru';
  static const String maintenanceEndTime = 'maintenance_end_time';

  static const String latestVersionAndroid = 'latest_version_android';
  static const String latestVersionIos = 'latest_version_ios';
  static const String minVersionAndroid = 'min_version_android';
  static const String minVersionIos = 'min_version_ios';

  static const String updateMessageEn = 'update_message_en';
  static const String updateMessageTr = 'update_message_tr';
  static const String updateMessageRu = 'update_message_ru';

  static const String releaseNotesEn = 'release_notes_en';
  static const String releaseNotesTr = 'release_notes_tr';
  static const String releaseNotesRu = 'release_notes_ru';

  static const String storeUrlAndroid = 'store_url_android';
  static const String storeUrlIos = 'store_url_ios';
}

/// Singleton service for checking app version and maintenance status
class VersionCheckService {
  VersionCheckService._internal();

  static final VersionCheckService _instance = VersionCheckService._internal();
  static VersionCheckService get instance => _instance;

  // Dependencies
  FirebaseRemoteConfig? _remoteConfig;
  PackageInfo? _packageInfo;
  static const String _skippedVersionKey = 'skipped_app_version';
  // State
  bool _isInitialized = false;
  bool _isInitializing = false;
  VersionCheckResult? _cachedResult;
  DateTime? _lastCheckTime;
  Completer<void>? _initCompleter;

  // Configuration
  static const Duration _fetchTimeout = Duration(seconds: 10);
  static const Duration _cacheExpiration = Duration(minutes: 5);
  static const Duration _minCheckInterval = Duration(minutes: 1);

  /// Initialize the service - call this once during app startup
  Future<void> initialize() async {
    // Prevent multiple simultaneous initializations
    if (_isInitializing) {
      await _initCompleter?.future;
      return;
    }

    if (_isInitialized) return;

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      // Get package info
      _packageInfo = await PackageInfo.fromPlatform();

      // Initialize Remote Config
      _remoteConfig = FirebaseRemoteConfig.instance;

      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: _fetchTimeout,
          minimumFetchInterval: Duration.zero, // ✅ Always fetch fresh
        ),
      );

      // Set default values
      await _remoteConfig!.setDefaults(_getDefaultValues());

      // Initial fetch
      await _fetchAndActivate();

      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('✅ VersionCheckService initialized successfully');
        debugPrint('📱 Current version: ${_packageInfo!.version}');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ VersionCheckService initialization error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      // Mark as initialized anyway to prevent blocking the app
      _isInitialized = true;
    } finally {
      _isInitializing = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    }
  }

  /// Default values for Remote Config
  Map<String, dynamic> _getDefaultValues() {
    return {
      _RemoteConfigKeys.maintenanceMode: false,
      _RemoteConfigKeys.maintenanceMessageEn:
          'We are currently performing maintenance. Please try again later.',
      _RemoteConfigKeys.maintenanceMessageTr:
          'Şu anda bakım yapıyoruz. Lütfen daha sonra tekrar deneyin.',
      _RemoteConfigKeys.maintenanceMessageRu:
          'В настоящее время проводятся технические работы. Пожалуйста, попробуйте позже.',
      _RemoteConfigKeys.maintenanceEndTime: '',
      _RemoteConfigKeys.latestVersionAndroid: '1.0.0',
      _RemoteConfigKeys.latestVersionIos: '1.0.0',
      _RemoteConfigKeys.minVersionAndroid: '1.0.0',
      _RemoteConfigKeys.minVersionIos: '1.0.0',
      _RemoteConfigKeys.updateMessageEn:
          'A new version is available. Update now for the best experience.',
      _RemoteConfigKeys.updateMessageTr:
          'Yeni bir sürüm mevcut. En iyi deneyim için şimdi güncelleyin.',
      _RemoteConfigKeys.updateMessageRu:
          'Доступна новая версия. Обновите сейчас для лучшего опыта.',
      _RemoteConfigKeys.releaseNotesEn: '',
      _RemoteConfigKeys.releaseNotesTr: '',
      _RemoteConfigKeys.releaseNotesRu: '',
      _RemoteConfigKeys.storeUrlAndroid: '',
      _RemoteConfigKeys.storeUrlIos: '',
    };
  }

  /// Fetch and activate remote config values
  Future<bool> _fetchAndActivate() async {
    try {
      final activated = await _remoteConfig!.fetchAndActivate();
      if (kDebugMode) {
        debugPrint(
          '🔄 Remote Config fetch: ${activated ? "activated" : "no changes"}',
        );
      }
      return activated;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Remote Config fetch failed: $e');
      }
      return false;
    }
  }

  Future<bool> _hasSkippedVersion(String latestVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final skippedVersion = prefs.getString(_skippedVersionKey);
    return skippedVersion == latestVersion;
  }

  /// Save that user skipped this version
  Future<void> markVersionAsSkipped(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedVersionKey, version);
  }

  /// Clear skipped version (call when user updates)
  Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skippedVersionKey);
  }

  /// Check version and return the appropriate state
  /// [languageCode] - Current app language (en, tr, ru)
  /// [forceRefresh] - Force a new fetch from Remote Config
  Future<VersionCheckResult> checkVersion({
    required String languageCode,
    bool forceRefresh = false,
  }) async {
    // Ensure service is initialized
    if (!_isInitialized) {
      await initialize();
    }

    // ✅ Always fetch fresh data on first check of session
    if (_lastCheckTime == null || forceRefresh) {
      await _fetchAndActivate();
    }

    // Return cached result if valid and not forcing refresh
    if (!forceRefresh && _cachedResult != null && _lastCheckTime != null) {
      final timeSinceLastCheck = DateTime.now().difference(_lastCheckTime!);
      if (timeSinceLastCheck < _minCheckInterval) {
        if (kDebugMode) {
          debugPrint('📦 Returning cached version check result');
        }
        return _cachedResult!;
      }
    }

    final result = _performVersionCheck(languageCode);

    if (result.state == AppUpdateState.softUpdate) {
      if (await _hasSkippedVersion(result.latestVersion)) {
        return VersionCheckResult(
          state: AppUpdateState.upToDate,
          currentVersion: result.currentVersion,
          latestVersion: result.latestVersion,
        );
      }
    }

    _cachedResult = result;
    _lastCheckTime = DateTime.now();

    return result;
  }

  /// Perform the actual version comparison
  VersionCheckResult _performVersionCheck(String languageCode) {
    if (_remoteConfig == null || _packageInfo == null) {
      return VersionCheckResult(
        state: AppUpdateState.upToDate,
        currentVersion: _packageInfo?.version ?? 'Unknown',
        latestVersion: 'Unknown',
      );
    }

    final currentVersion = _packageInfo!.version;

    // Check maintenance mode first (highest priority)
    final isMaintenanceMode =
        _remoteConfig!.getBool(_RemoteConfigKeys.maintenanceMode);
    if (isMaintenanceMode) {
      return VersionCheckResult(
        state: AppUpdateState.maintenance,
        currentVersion: currentVersion,
        latestVersion: _getLatestVersion(),
        maintenanceMessage: _getMaintenanceMessage(languageCode),
        maintenanceEndTime: _getMaintenanceEndTime(),
      );
    }

    // Get version requirements based on platform
    final latestVersion = _getLatestVersion();
    final minVersion = _getMinVersion();

    // Compare versions
    final currentParsed = _parseVersion(currentVersion);
    final latestParsed = _parseVersion(latestVersion);
    final minParsed = _parseVersion(minVersion);

    // Check for force update (current < minimum)
    if (_isVersionLower(currentParsed, minParsed)) {
      return VersionCheckResult(
        state: AppUpdateState.forceUpdate,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        updateMessage: _getUpdateMessage(languageCode),
        storeUrl: _getStoreUrl(),
        releaseNotes: _getReleaseNotes(languageCode),
      );
    }

    // Check for soft update (current < latest but >= minimum)
    if (_isVersionLower(currentParsed, latestParsed)) {
      return VersionCheckResult(
        state: AppUpdateState.softUpdate,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        updateMessage: _getUpdateMessage(languageCode),
        storeUrl: _getStoreUrl(),
        releaseNotes: _getReleaseNotes(languageCode),
      );
    }

    // App is up to date
    return VersionCheckResult(
      state: AppUpdateState.upToDate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
    );
  }

  /// Get the latest version for current platform
  String _getLatestVersion() {
    if (Platform.isAndroid) {
      return _remoteConfig!.getString(_RemoteConfigKeys.latestVersionAndroid);
    } else if (Platform.isIOS) {
      return _remoteConfig!.getString(_RemoteConfigKeys.latestVersionIos);
    }
    return '1.0.0';
  }

  /// Get the minimum required version for current platform
  String _getMinVersion() {
    if (Platform.isAndroid) {
      return _remoteConfig!.getString(_RemoteConfigKeys.minVersionAndroid);
    } else if (Platform.isIOS) {
      return _remoteConfig!.getString(_RemoteConfigKeys.minVersionIos);
    }
    return '1.0.0';
  }

  /// Get localized maintenance message
  String _getMaintenanceMessage(String languageCode) {
    switch (languageCode) {
      case 'tr':
        return _remoteConfig!.getString(_RemoteConfigKeys.maintenanceMessageTr);
      case 'ru':
        return _remoteConfig!.getString(_RemoteConfigKeys.maintenanceMessageRu);
      default:
        return _remoteConfig!.getString(_RemoteConfigKeys.maintenanceMessageEn);
    }
  }

  /// Get localized update message
  String _getUpdateMessage(String languageCode) {
    switch (languageCode) {
      case 'tr':
        return _remoteConfig!.getString(_RemoteConfigKeys.updateMessageTr);
      case 'ru':
        return _remoteConfig!.getString(_RemoteConfigKeys.updateMessageRu);
      default:
        return _remoteConfig!.getString(_RemoteConfigKeys.updateMessageEn);
    }
  }

  /// Get localized release notes
  List<String> _getReleaseNotes(String languageCode) {
    String notes;
    switch (languageCode) {
      case 'tr':
        notes = _remoteConfig!.getString(_RemoteConfigKeys.releaseNotesTr);
        break;
      case 'ru':
        notes = _remoteConfig!.getString(_RemoteConfigKeys.releaseNotesRu);
        break;
      default:
        notes = _remoteConfig!.getString(_RemoteConfigKeys.releaseNotesEn);
    }

    if (notes.isEmpty) return [];

    // Split by newline and filter empty lines
    return notes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Get maintenance end time if set
  DateTime? _getMaintenanceEndTime() {
    final endTimeStr =
        _remoteConfig!.getString(_RemoteConfigKeys.maintenanceEndTime);
    if (endTimeStr.isEmpty) return null;

    try {
      return DateTime.parse(endTimeStr);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to parse maintenance end time: $e');
      }
      return null;
    }
  }

  /// Get store URL for current platform
  String? _getStoreUrl() {
    String url;
    if (Platform.isAndroid) {
      url = _remoteConfig!.getString(_RemoteConfigKeys.storeUrlAndroid);
    } else if (Platform.isIOS) {
      url = _remoteConfig!.getString(_RemoteConfigKeys.storeUrlIos);
    } else {
      return null;
    }
    return url.isNotEmpty ? url : null;
  }

  /// Parse version string to comparable list
  /// Handles formats like "1.0.0", "1.0.0+1", "1.0"
  List<int> _parseVersion(String version) {
    // Remove build number if present
    final versionOnly = version.split('+').first;

    final parts = versionOnly.split('.');
    final result = <int>[];

    for (final part in parts) {
      try {
        result.add(int.parse(part));
      } catch (e) {
        result.add(0);
      }
    }

    // Ensure at least 3 parts (major.minor.patch)
    while (result.length < 3) {
      result.add(0);
    }

    return result;
  }

  /// Compare two parsed versions
  /// Returns true if v1 < v2
  bool _isVersionLower(List<int> v1, List<int> v2) {
    final maxLength = v1.length > v2.length ? v1.length : v2.length;

    for (var i = 0; i < maxLength; i++) {
      final part1 = i < v1.length ? v1[i] : 0;
      final part2 = i < v2.length ? v2[i] : 0;

      if (part1 < part2) return true;
      if (part1 > part2) return false;
    }

    return false; // Versions are equal
  }

  /// Clear cached result (useful for testing or manual refresh)
  void clearCache() {
    _cachedResult = null;
    _lastCheckTime = null;
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get current package info
  PackageInfo? get packageInfo => _packageInfo;
}

// lib/providers/search_history_provider.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/search_entry.dart';

/// Production-ready SearchHistoryProvider using optimistic local-first pattern.
///
/// Key features:
/// - One-time fetch instead of real-time listener (saves reads)
/// - Optimistic UI updates for instant feedback
/// - Session caching to avoid redundant fetches
/// - Proper error handling with rollback
/// - Deduplication of search terms
class SearchHistoryProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ==================== CONFIGURATION ====================
  static const int _maxHistoryItems = 20;
  static const int _batchDeleteSize = 500;
  static const Duration _deleteTimeout = Duration(seconds: 10);
  static const int _maxDeleteRetries = 3;

  // ==================== STATE ====================
  List<SearchEntry> _entries = [];
  List<SearchEntry> get searchEntries => List.unmodifiable(_entries);

  String? _currentUserId;
  bool _isLoadingHistory = false;
  bool get isLoadingHistory => _isLoadingHistory;

  /// Tracks if we've fetched history this session (avoids redundant fetches)
  bool _hasFetchedThisSession = false;

  /// Track items being deleted (for UI loading indicators)
  final Set<String> _deletingEntryIds = <String>{};

  /// Track optimistically deleted items (hidden from UI immediately)
  final Set<String> _optimisticallyDeletedIds = <String>{};

  /// Auth subscription for login/logout handling
  StreamSubscription<User?>? _authSubscription;

  // ==================== CONSTRUCTOR ====================

  SearchHistoryProvider() {
    _initAuthListener();
  }

  // ==================== PUBLIC GETTERS ====================

  bool isDeletingEntry(String docId) => _deletingEntryIds.contains(docId);

  bool get hasEntries => _entries.isNotEmpty;

  int get entryCount => _entries.length;

  // ==================== AUTH HANDLING ====================

  void _initAuthListener() {
    // Check current user immediately
    final currentUser = _auth.currentUser;
    _currentUserId = currentUser?.uid;

    // Listen for auth changes (login/logout/switch account)
    _authSubscription = _auth.authStateChanges().listen(_handleAuthChange);
  }

  void _handleAuthChange(User? user) {
    final newUserId = user?.uid;

    // Only react if user actually changed
    if (newUserId == _currentUserId) return;

    _currentUserId = newUserId;

    // Clear all state for user change
    _entries = [];
    _hasFetchedThisSession = false;
    _deletingEntryIds.clear();
    _optimisticallyDeletedIds.clear();
    _isLoadingHistory = false;

    notifyListeners();
  }

  // ==================== FETCH HISTORY ====================

  /// Ensures history is loaded. Call this when search UI opens.
  /// Uses session caching - only fetches once per session unless forced.
  Future<void> ensureLoaded({bool forceRefresh = false}) async {
    // Guard: No user logged in
    if (_currentUserId == null) {
      _entries = [];
      notifyListeners();
      return;
    }

    // Guard: Already loaded this session (unless forcing refresh)
    if (_hasFetchedThisSession && !forceRefresh) {
      return;
    }

    // Guard: Already loading
    if (_isLoadingHistory) return;

    _isLoadingHistory = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('searches')
          .where('userId', isEqualTo: _currentUserId)
          .orderBy('timestamp', descending: true)
          .limit(_maxHistoryItems)
          .get();

      // Parse and deduplicate entries
      final fetchedEntries =
          snapshot.docs.map((doc) => SearchEntry.fromFirestore(doc)).toList();

      _entries = _deduplicateEntries(fetchedEntries);
      _hasFetchedThisSession = true;

      // Clear optimistic deletes that are confirmed
      _cleanupConfirmedDeletes(snapshot.docs.map((d) => d.id).toSet());

      if (kDebugMode) {
        debugPrint('✅ Loaded ${_entries.length} search history entries');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error fetching search history: $e');
      }
      // Keep existing entries on error (don't clear user's view)
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  /// Force refresh history from server
  Future<void> refresh() async {
    await ensureLoaded(forceRefresh: true);
  }

  // ==================== ADD SEARCH ====================

  /// Adds a search term with optimistic local update.
  /// Writes to Firestore in background (fire-and-forget).
  void addSearch(String term) {
    final trimmedTerm = term.trim();

    // Guard: Empty term or no user
    if (trimmedTerm.isEmpty || _currentUserId == null) return;

    // Check if term already exists (case-insensitive)
    final existingIndex = _entries.indexWhere(
      (e) => e.searchTerm.toLowerCase() == trimmedTerm.toLowerCase(),
    );

    if (existingIndex != -1) {
      // Move existing entry to top (update timestamp locally)
      final existing = _entries.removeAt(existingIndex);
      final updated = SearchEntry(
        id: existing.id,
        searchTerm: existing.searchTerm,
        timestamp: DateTime.now(),
        userId: existing.userId,
      );
      _entries.insert(0, updated);
      notifyListeners();

      // Update timestamp in Firestore (fire-and-forget)
      _updateTimestampInFirestore(existing.id);
      return;
    }

    // Create new entry with temporary local ID
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final newEntry = SearchEntry(
      id: localId,
      searchTerm: trimmedTerm,
      timestamp: DateTime.now(),
      userId: _currentUserId!,
    );

    // Optimistic local update (instant UI)
    _entries.insert(0, newEntry);

    // Enforce max items limit
    if (_entries.length > _maxHistoryItems) {
      _entries = _entries.take(_maxHistoryItems).toList();
    }

    notifyListeners();

    // Fire-and-forget write to Firestore
    _addToFirestore(trimmedTerm, localId);
  }

  Future<void> _addToFirestore(String term, String localId) async {
    try {
      final docRef = await _firestore.collection('searches').add({
        'userId': _currentUserId,
        'searchTerm': term,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update local entry with real Firestore ID
      final index = _entries.indexWhere((e) => e.id == localId);
      if (index != -1) {
        _entries[index] = SearchEntry(
          id: docRef.id,
          searchTerm: _entries[index].searchTerm,
          timestamp: _entries[index].timestamp,
          userId: _entries[index].userId,
        );
        // No need to notify - ID change is invisible to user
      }

      if (kDebugMode) {
        debugPrint('✅ Search term saved: $term');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to save search term (offline?): $e');
      }
      // Keep local entry even if Firestore write fails
      // It will be visible until next refresh
    }
  }

  Future<void> _updateTimestampInFirestore(String docId) async {
    // Skip local IDs
    if (docId.startsWith('local_')) return;

    try {
      await _firestore.collection('searches').doc(docId).update({
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to update timestamp: $e');
      }
    }
  }

  // ==================== DELETE SINGLE ENTRY ====================

  /// Deletes a single entry with optimistic UI update and rollback on failure.
  Future<void> deleteEntry(String docId) async {
    // Guard: Already deleting this entry
    if (_deletingEntryIds.contains(docId)) {
      if (kDebugMode) {
        debugPrint('Delete already in progress for: $docId');
      }
      return;
    }

    // Find entry for potential rollback
    final index = _entries.indexWhere((e) => e.id == docId);
    if (index == -1) return; // Entry not found

    final entryBackup = _entries[index];

    // Mark as deleting (for UI loading indicator)
    _deletingEntryIds.add(docId);

    // Optimistic removal (instant UI update)
    _optimisticallyDeletedIds.add(docId);
    _entries.removeAt(index);
    notifyListeners();

    try {
      // Skip Firestore delete for local-only entries
      if (!docId.startsWith('local_')) {
        await _deleteFromFirestoreWithRetry(docId);
      }

      // Success - clean up tracking
      _optimisticallyDeletedIds.remove(docId);

      if (kDebugMode) {
        debugPrint('✅ Deleted search entry: $docId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to delete entry: $e');
      }

      // Rollback: restore entry to original position
      _optimisticallyDeletedIds.remove(docId);
      if (index <= _entries.length) {
        _entries.insert(index, entryBackup);
      } else {
        _entries.add(entryBackup);
      }
      notifyListeners();

      rethrow;
    } finally {
      _deletingEntryIds.remove(docId);
      notifyListeners();
    }
  }

  Future<void> _deleteFromFirestoreWithRetry(String docId) async {
    int attempts = 0;

    while (attempts < _maxDeleteRetries) {
      try {
        await _firestore
            .collection('searches')
            .doc(docId)
            .delete()
            .timeout(_deleteTimeout);
        return; // Success
      } catch (e) {
        attempts++;

        if (attempts >= _maxDeleteRetries) {
          rethrow;
        }

        if (kDebugMode) {
          debugPrint('Delete attempt $attempts failed, retrying...');
        }

        // Exponential backoff
        await Future.delayed(Duration(milliseconds: 200 * attempts));
      }
    }
  }

  // ==================== DELETE ALL ====================

  /// Clears all search history for current user.
  Future<void> deleteAllForCurrentUser() async {
    if (_currentUserId == null) return;

    // Backup for rollback
    final entriesBackup = List<SearchEntry>.from(_entries);

    // Optimistic clear (instant UI)
    _entries = [];
    _optimisticallyDeletedIds.clear();
    notifyListeners();

    try {
      // Fetch all user's search docs
      final snapshot = await _firestore
          .collection('searches')
          .where('userId', isEqualTo: _currentUserId)
          .get();

      if (snapshot.docs.isEmpty) return;

      // Batch delete (Firestore limit is 500 per batch)
      for (var i = 0; i < snapshot.docs.length; i += _batchDeleteSize) {
        final batch = _firestore.batch();
        final chunk = snapshot.docs.skip(i).take(_batchDeleteSize);

        for (final doc in chunk) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }

      if (kDebugMode) {
        debugPrint(
            '✅ Deleted all search history (${snapshot.docs.length} entries)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to delete all history: $e');
      }

      // Rollback on failure
      _entries = entriesBackup;
      notifyListeners();

      rethrow;
    }
  }

  // ==================== LOCAL ENTRY (for external insertion) ====================

  /// Inserts a local entry directly (used by search delegate for immediate feedback).
  /// Prefer using addSearch() which handles deduplication and Firestore write.
  void insertLocalEntry(SearchEntry entry) {
    if (_currentUserId == null) return;

    // Remove duplicate if exists
    _entries.removeWhere(
      (e) => e.searchTerm.toLowerCase() == entry.searchTerm.toLowerCase(),
    );

    _entries.insert(0, entry);

    if (_entries.length > _maxHistoryItems) {
      _entries = _entries.take(_maxHistoryItems).toList();
    }

    notifyListeners();
  }

  // ==================== HELPERS ====================

  /// Removes duplicate search terms, keeping the most recent.
  List<SearchEntry> _deduplicateEntries(List<SearchEntry> entries) {
    final seen = <String>{};
    final result = <SearchEntry>[];

    for (final entry in entries) {
      final normalizedTerm = entry.searchTerm.toLowerCase();
      if (!seen.contains(normalizedTerm)) {
        seen.add(normalizedTerm);
        result.add(entry);
      }
    }

    return result;
  }

  /// Cleans up optimistic deletes that are confirmed deleted from Firestore.
  void _cleanupConfirmedDeletes(Set<String> existingDocIds) {
    _optimisticallyDeletedIds.removeWhere((id) => !existingDocIds.contains(id));
  }

  /// Clears all local state (called on logout).
  void clearHistory() {
    _entries = [];
    _hasFetchedThisSession = false;
    _deletingEntryIds.clear();
    _optimisticallyDeletedIds.clear();
    _isLoadingHistory = false;
    notifyListeners();
  }

  // ==================== DISPOSE ====================

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;

    _entries = [];
    _deletingEntryIds.clear();
    _optimisticallyDeletedIds.clear();

    super.dispose();
  }
}

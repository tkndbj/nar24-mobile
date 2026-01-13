// lib/providers/search_history_provider.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/search_entry.dart';

class SearchHistoryProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<QuerySnapshot>? _historySubscription;
  StreamSubscription<User?>? _authSubscription;

  List<SearchEntry> _searchEntriesSearches = [];
  List<SearchEntry> _searchEntries = [];
  List<SearchEntry> get searchEntries => _searchEntries;

  String? _currentUserId;

  // Loading state for history
  bool _isLoadingHistory = false;
  bool get isLoadingHistory => _isLoadingHistory;

  // Track items being deleted with more granular control
  final Map<String, Completer<void>> _deletingEntries =
      <String, Completer<void>>{};
  final Set<String> _optimisticallyDeleted = <String>{};

  bool isDeletingEntry(String docId) => _deletingEntries.containsKey(docId);

  SearchHistoryProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    // Check current user immediately when provider is created
    final currentUser = _auth.currentUser;
    _currentUserId = currentUser?.uid;

    if (_currentUserId != null) {
      // Clear any stale data before fetching
      _searchEntriesSearches = [];
      _searchEntries = [];
      _isLoadingHistory = true;
      notifyListeners();
      fetchSearchHistory(_currentUserId!);
    } else {
      clearHistory(); // Clear immediately if no user
    }

    // Then listen for future auth changes
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      final newUserId = user?.uid;

      // If user changed (login/logout/switch), clear and reload
      if (newUserId != _currentUserId) {
        _currentUserId = newUserId;

        if (newUserId != null) {
          // Clear any stale data before fetching new user's history
          // This prevents briefly showing old/cached data while loading
          _searchEntriesSearches = [];
          _searchEntries = [];
          _isLoadingHistory = true;
          notifyListeners();
          fetchSearchHistory(newUserId);
        } else {
          clearHistory();
        }
      }
    });
  }

  void fetchSearchHistory(String userId) {
    _historySubscription?.cancel();

    _historySubscription = _firestore
        .collection('searches')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      _searchEntriesSearches =
          snapshot.docs.map((doc) => SearchEntry.fromFirestore(doc)).toList();
      _isLoadingHistory = false;

      // Remove any optimistically deleted items that are confirmed deleted
      _cleanupOptimisticDeletes(snapshot.docs.map((doc) => doc.id).toSet());

      _updateCombinedEntries();
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint('Error fetching search history: $error');
      }
      _isLoadingHistory = false;
      notifyListeners();
    });
  }

  void _cleanupOptimisticDeletes(Set<String> existingDocIds) {
    // Remove optimistically deleted items that are confirmed deleted from Firestore
    final toRemove = _optimisticallyDeleted
        .where((id) => !existingDocIds.contains(id))
        .toList();
    for (final id in toRemove) {
      _optimisticallyDeleted.remove(id);
    }
  }

  void insertLocalEntry(SearchEntry entry) {
    // Only insert if we have a current user
    if (_currentUserId != null) {
      _searchEntriesSearches.insert(0, entry);
      _updateCombinedEntries();
    }
  }

  void _updateCombinedEntries() {
    // Filter out optimistically deleted entries
    final filteredEntries = _searchEntriesSearches
        .where((entry) => !_optimisticallyDeleted.contains(entry.id))
        .toList();

    final combinedEntries = [...filteredEntries];
    final Map<String, SearchEntry> uniqueMap = {};

    for (var entry in combinedEntries) {
      if (!uniqueMap.containsKey(entry.searchTerm)) {
        uniqueMap[entry.searchTerm] = entry;
      }
    }

    _searchEntries = uniqueMap.values.toList()
      ..sort((a, b) => (b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0)));
    notifyListeners();
  }

  void clearHistory() {
    _historySubscription?.cancel();
    _historySubscription = null;
    _searchEntriesSearches = [];
    _searchEntries = [];
    _isLoadingHistory = false;
    _deletingEntries.clear();
    _optimisticallyDeleted.clear();
    notifyListeners();
  }

  Future<void> deleteEntry(String docId) async {
    // If already deleting, wait for that operation to complete
    if (_deletingEntries.containsKey(docId)) {
      if (kDebugMode) {
        debugPrint('Delete already in progress for entry: $docId, waiting...');
      }
      await _deletingEntries[docId]!.future;
      return;
    }

    // Create a completer for this delete operation
    final completer = Completer<void>();
    _deletingEntries[docId] = completer;

    try {
      if (kDebugMode) {
        debugPrint('Starting delete operation for entry: $docId');
      }

      // Step 1: Immediately hide from UI (optimistic update)
      _optimisticallyDeleted.add(docId);
      _updateCombinedEntries(); // This will filter out the deleted item

      // Step 2: Delete from Firestore with timeout
      await _deleteFromFirestore(docId).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
              'Delete operation timed out', const Duration(seconds: 10));
        },
      );

      if (kDebugMode) {
        debugPrint('Successfully deleted search entry: $docId');
      }
      completer.complete();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting search entry $docId: $e');
      }

      // Rollback: restore the item in UI
      _optimisticallyDeleted.remove(docId);
      _updateCombinedEntries();

      completer.completeError(e);
      rethrow;
    } finally {
      // Always clean up
      _deletingEntries.remove(docId);
      notifyListeners(); // Update UI to remove loading indicator
    }
  }

  Future<void> _deleteFromFirestore(String docId) async {
    // Retry logic for network issues
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        await _firestore.collection('searches').doc(docId).delete();
        return; // Success, exit retry loop
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          throw e; // Give up after max retries
        }

        if (kDebugMode) {
          debugPrint('Delete attempt $retryCount failed, retrying: $e');
        }
        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(milliseconds: 200 * retryCount));
      }
    }
  }

  Future<void> deleteAllForCurrentUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      await deleteAllForUser(currentUser.uid);
    }
  }

  Future<void> deleteAllForUser(String userId) async {
    try {
      // Optimistically clear the UI first
      final originalEntries = List<SearchEntry>.from(_searchEntriesSearches);
      _searchEntriesSearches.clear();
      _searchEntries.clear();
      _optimisticallyDeleted.clear();
      notifyListeners();

      // Then delete from Firestore
      final snapshot = await _firestore
          .collection('searches')
          .where('userId', isEqualTo: userId)
          .get();
      final docs = snapshot.docs;

      const batchSize = 500;
      for (var i = 0; i < docs.length; i += batchSize) {
        final batch = _firestore.batch();
        for (var doc in docs.skip(i).take(batchSize)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      if (kDebugMode) {
        debugPrint('Successfully deleted all search history for user: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting all search history: $e');
      }
      // The Firestore listener will restore the correct state
      rethrow;
    }
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    _authSubscription?.cancel();

    // Complete any pending delete operations
    for (final completer in _deletingEntries.values) {
      if (!completer.isCompleted) {
        completer.completeError('Provider disposed');
      }
    }

    _deletingEntries.clear();
    _optimisticallyDeleted.clear();
    super.dispose();
  }
}

class TimeoutException implements Exception {
  final String message;
  final Duration timeout;

  const TimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message after ${timeout.inSeconds}s';
}

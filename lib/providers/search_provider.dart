// lib/providers/search_provider.dart - With Pagination + Autocomplete Support
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import '../models/suggestion.dart';
import '../models/category_suggestion.dart';
import '../models/shop_suggestion.dart';
import '../services/typesense_service_manager.dart';
import '../services/enhanced_category_search.dart';
import '../../generated/l10n/app_localizations.dart';
import '../utils/connectivity_helper.dart';
import '../services/search_config_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SearchProvider extends ChangeNotifier {
  // ==================== CONFIGURATION ====================
  static const int _initialPageSize = 10;
  static const int _loadMorePageSize = 5;
  static const int _maxSuggestions = 20;

  /// Number of autocomplete name chips shown above results.
  static const int _autocompleteLimit = 5;

  // ==================== STATE ====================
  String _term = '';
  List<Suggestion> _suggestions = [];
  List<CategorySuggestion> _categorySuggestions = [];
  List<ShopSuggestion> _shopSuggestions = [];

  // Autocomplete state
  List<String> _autocompleteSuggestions = [];

  // Pagination state
  int _currentProductCount = 0;
  bool _hasMoreProducts = true;
  bool _isLoadingMore = false;
  String? _lastSearchTerm;

  // Debounce pipelines
  //
  // Two separate subjects let us tune debounce independently:
  //  • _autocompleteSubject fires faster (150 ms) for instant chip updates.
  //  • _querySubject fires at 300 ms for the heavier multi-fetch.
  final _querySubject = BehaviorSubject<String>();
  final _autocompleteSubject = BehaviorSubject<String>();

  // Loading & Error state
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasNetworkError = false;
  bool _disposed = false;

  TypeSenseServiceManager get _typesenseManager =>
      TypeSenseServiceManager.instance;

  SearchProvider() {
    // Heavy search pipeline – 300 ms debounce
    _querySubject
        .debounceTime(const Duration(milliseconds: 300))
        .listen((term) {
      if (term.isEmpty) {
        _clearResults();
      } else {
        _performInitialSearch(term, null);
      }
    });

    // Lightweight autocomplete pipeline – 150 ms debounce.
    // Skipped entirely when Firestore fallback mode is active.
    _autocompleteSubject
        .debounceTime(const Duration(milliseconds: 150))
        .listen((term) {
      if (term.isEmpty) {
        _clearAutocompleteSuggestions();
      } else if (!SearchConfigService.instance.useFirestore) {
        _fetchAutocompleteSuggestions(term);
      }
    });
  }

  // ==================== GETTERS ====================
  String get term => _term;
  List<Suggestion> get suggestions => List.unmodifiable(_suggestions);
  List<CategorySuggestion> get categorySuggestions =>
      List.unmodifiable(_categorySuggestions);
  List<ShopSuggestion> get shopSuggestions =>
      List.unmodifiable(_shopSuggestions);

  /// Deduplicated product-name strings for autocomplete chips.
  /// Already filters out any name that exactly matches the current query
  /// to avoid showing a chip for what the user just typed.
  List<String> get autocompleteSuggestions {
    final queryLower = _term.toLowerCase();
    return _autocompleteSuggestions
        .where((s) => s.toLowerCase() != queryLower)
        .toList();
  }

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreProducts =>
      _hasMoreProducts && _suggestions.length < _maxSuggestions;
  String? get errorMessage => _errorMessage;
  bool get hasNetworkError => _hasNetworkError;
  bool get mounted => !_disposed;

  // ==================== PUBLIC METHODS ====================

  /// User-triggered immediate search (e.g. on submit / chip tap).
  void search(String searchTerm, {AppLocalizations? l10n}) {
    final trimmed = searchTerm.trim();
    _term = trimmed;

    if (trimmed.isEmpty) {
      _clearResults();
      return;
    }

    _clearAutocompleteSuggestions(notify: false);
    _setLoadingState();
    _performInitialSearch(trimmed, l10n);
  }

  /// Called on each keystroke to debounce both pipelines.
  void updateTerm(String newTerm, {AppLocalizations? l10n}) {
    final trimmed = newTerm.trim();
    _term = trimmed;

    if (trimmed.isEmpty) {
      _clearResults();
    } else {
      _setLoadingState();
    }

    // Fire both subjects; each has its own debounce.
    if (!_querySubject.isClosed) _querySubject.add(trimmed);
    if (!_autocompleteSubject.isClosed) _autocompleteSubject.add(trimmed);
  }

  /// Load more product suggestions (pagination).
  Future<void> loadMoreSuggestions({AppLocalizations? l10n}) async {
    if (!mounted) return;
    if (_isLoadingMore) return;
    if (!_hasMoreProducts) return;
    if (_suggestions.length >= _maxSuggestions) return;
    if (_term.isEmpty) return;

    // No pagination in Firestore fallback mode
    if (SearchConfigService.instance.useFirestore) {
      _hasMoreProducts = false;
      notifyListeners();
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    try {
      final isConnected = await ConnectivityHelper.isConnected()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);

      if (!isConnected) {
        _isLoadingMore = false;
        notifyListeners();
        return;
      }

      final remaining = _maxSuggestions - _suggestions.length;
      final fetchCount =
          remaining < _loadMorePageSize ? remaining : _loadMorePageSize;

      final newSuggestions = await _fetchMoreProductSuggestions(
        _term,
        offset: _currentProductCount,
        limit: fetchCount,
      );

      if (!mounted || _term != _lastSearchTerm) {
        _isLoadingMore = false;
        return;
      }

      if (newSuggestions.isEmpty) {
        _hasMoreProducts = false;
      } else {
        final existingIds = _suggestions.map((s) => s.id).toSet();
        final uniqueNew =
            newSuggestions.where((s) => !existingIds.contains(s.id)).toList();

        _suggestions = [..._suggestions, ...uniqueNew];
        _currentProductCount += newSuggestions.length;

        if (newSuggestions.length < fetchCount) {
          _hasMoreProducts = false;
        }
      }

      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Load more error: $e');
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void clear() {
    if (_disposed) return;
    _term = '';
    _clearResults();
    _clearAutocompleteSuggestions(notify: false);
    if (!_querySubject.isClosed) _querySubject.add('');
    if (!_autocompleteSubject.isClosed) _autocompleteSubject.add('');
  }

  void clearError() {
    if (!mounted) return;
    _errorMessage = null;
    _hasNetworkError = false;
    notifyListeners();
  }

  Future<void> retry({AppLocalizations? l10n}) async {
    if (!mounted) return;
    final current = _term.trim();
    if (current.isNotEmpty) {
      _setLoadingState();
      await _performInitialSearch(current, l10n);
    } else {
      _clearResults();
    }
  }

  // ==================== PRIVATE: AUTOCOMPLETE ====================

  /// Fetches a small list of product names from the main Typesense index
  /// to populate the autocomplete chips. Errors are swallowed intentionally
  /// because autocomplete is a non-critical enhancement.
  Future<void> _fetchAutocompleteSuggestions(String searchTerm) async {
    if (!mounted || searchTerm.isEmpty) return;

    try {
      final names = await _typesenseManager.mainService
          .searchQuerySuggestions(
            query: searchTerm,
            hitsPerPage: _autocompleteLimit,
          )
          .timeout(const Duration(seconds: 3));

      // Discard stale results if the user has since cleared or changed query.
      if (!mounted || _term != searchTerm) return;

      _autocompleteSuggestions = names;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Autocomplete fetch error: $e');
      // Silently discard – do not pollute error state.
    }
  }

  void _clearAutocompleteSuggestions({bool notify = true}) {
    if (_autocompleteSuggestions.isEmpty) return;
    _autocompleteSuggestions = [];
    if (notify && mounted) notifyListeners();
  }

  // ==================== PRIVATE: CORE SEARCH ====================

  void _clearResults() {
    _suggestions = [];
    _categorySuggestions = [];
    _shopSuggestions = [];
    _autocompleteSuggestions = [];
    _currentProductCount = 0;
    _hasMoreProducts = true;
    _isLoadingMore = false;
    _lastSearchTerm = null;
    _isLoading = false;
    _errorMessage = null;
    _hasNetworkError = false;
    if (!_disposed && mounted) notifyListeners();
  }

  void _setLoadingState() {
    _isLoading = true;
    _errorMessage = null;
    _hasNetworkError = false;
    if (mounted) notifyListeners();
  }

  void _resetPagination() {
    _currentProductCount = 0;
    _hasMoreProducts = true;
    _isLoadingMore = false;
  }

  Future<void> _performInitialSearch(
      String searchTerm, AppLocalizations? l10n) async {
    if (!mounted || searchTerm.isEmpty) return;

    _resetPagination();
    _lastSearchTerm = searchTerm;

    try {
      final isConnected = await ConnectivityHelper.isConnected()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);

      if (!isConnected) {
        _handleError(
          l10n?.searchNetworkError ?? 'No internet connection',
          isNetworkError: true,
        );
        return;
      }

      // Firestore fallback mode – only products, no categories/shops.
      if (SearchConfigService.instance.useFirestore) {
        final productSuggestions = await _fetchProductSuggestionsFirestore(
            searchTerm,
            limit: _initialPageSize);

        if (mounted && _term == searchTerm) {
          _suggestions = productSuggestions;
          _categorySuggestions = [];
          _shopSuggestions = [];
          _currentProductCount = productSuggestions.length;
          if (productSuggestions.length < _initialPageSize) {
            _hasMoreProducts = false;
          }
          _isLoading = false;
          notifyListeners();
        }
        return;
      }

      final results = await Future.wait([
        _fetchProductSuggestions(searchTerm, limit: _initialPageSize),
        _fetchEnhancedCategorySuggestions(searchTerm, l10n),
        _fetchShopSuggestions(searchTerm, l10n),
      ]).timeout(const Duration(seconds: 5));

      final productSuggestions = results[0] as List<Suggestion>;
      final categorySuggestions = results[1] as List<CategorySuggestion>;
      final shopSuggestions = results[2] as List<ShopSuggestion>;

      if (mounted && _term == searchTerm) {
        _suggestions = productSuggestions;
        _categorySuggestions = categorySuggestions;
        _shopSuggestions = shopSuggestions;
        _currentProductCount = productSuggestions.length;

        if (productSuggestions.length < _initialPageSize) {
          _hasMoreProducts = false;
        }

        _isLoading = false;
        _errorMessage = null;
        _hasNetworkError = false;
        notifyListeners();
      }
    } catch (e) {
      if (mounted && _term == searchTerm) {
        _handleError(
          l10n?.searchGeneralError ?? 'Search error occurred',
        );
      }
    }
  }

  Future<List<Suggestion>> _fetchProductSuggestionsFirestore(
    String searchTerm, {
    required int limit,
  }) async {
    try {
      final lower = searchTerm.toLowerCase();
      final capitalized = searchTerm.substring(0, 1).toUpperCase() +
          searchTerm.substring(1).toLowerCase();

      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('products')
            .orderBy('productName')
            .startAt([lower])
            .endAt(['$lower\uf8ff'])
            .limit(limit)
            .get(),
        FirebaseFirestore.instance
            .collection('products')
            .orderBy('productName')
            .startAt([capitalized])
            .endAt(['$capitalized\uf8ff'])
            .limit(limit)
            .get(),
        FirebaseFirestore.instance
            .collection('shop_products')
            .orderBy('productName')
            .startAt([lower])
            .endAt(['$lower\uf8ff'])
            .limit(limit)
            .get(),
        FirebaseFirestore.instance
            .collection('shop_products')
            .orderBy('productName')
            .startAt([capitalized])
            .endAt(['$capitalized\uf8ff'])
            .limit(limit)
            .get(),
      ]).timeout(const Duration(seconds: 5));

      final combined = <Suggestion>[];
      final seenIds = <String>{};

      for (final snapshot in results) {
        for (final doc in snapshot.docs) {
          if (combined.length >= limit) break;
          final data = doc.data();
          if (seenIds.add(doc.id)) {
            combined.add(Suggestion(
              id: doc.id,
              name: data['productName'] as String? ?? '',
              price: (data['price'] as num?)?.toDouble() ?? 0.0,
              imageUrl: (data['imageUrls'] as List?)?.isNotEmpty == true
                  ? (data['imageUrls'] as List).first as String?
                  : null,
            ));
          }
        }
      }
      return combined;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Firestore product suggestions error: $e');
      return [];
    }
  }

  Future<List<Suggestion>> _fetchProductSuggestions(
    String searchTerm, {
    required int limit,
  }) async {
    try {
      final results = await Future.wait([
        _typesenseManager.mainService
            .searchProducts(
              query: searchTerm,
              sortOption: '',
              page: 0,
              hitsPerPage: limit,
            )
            .timeout(const Duration(seconds: 3)),
        _typesenseManager.shopService
            .searchProducts(
              query: searchTerm,
              sortOption: '',
              page: 0,
              hitsPerPage: limit,
            )
            .timeout(const Duration(seconds: 3)),
      ]);

      return _combineProductResults(results, limit);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Product suggestions error: $e');
      return [];
    }
  }

  Future<List<Suggestion>> _fetchMoreProductSuggestions(
    String searchTerm, {
    required int offset,
    required int limit,
  }) async {
    try {
      final results = await Future.wait([
        _typesenseManager.mainService
            .searchProducts(
              query: searchTerm,
              sortOption: '',
              page: 0,
              hitsPerPage: _maxSuggestions,
            )
            .timeout(const Duration(seconds: 3)),
        _typesenseManager.shopService
            .searchProducts(
              query: searchTerm,
              sortOption: '',
              page: 0,
              hitsPerPage: _maxSuggestions,
            )
            .timeout(const Duration(seconds: 3)),
      ]);

      return _combineProductResults(results, limit);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Fetch more products error: $e');
      return [];
    }
  }

  List<Suggestion> _combineProductResults(List<dynamic> results, int limit) {
    final combined = <Suggestion>[];
    final seenIds = <String>{};

    for (final existing in _suggestions) {
      seenIds.add(existing.id);
    }

    for (final list in results) {
      for (final p in list) {
        if (combined.length >= limit) break;
        if (seenIds.add(p.id)) {
          combined.add(Suggestion(
            id: p.id,
            name: p.productName,
            price: p.price,
            imageUrl:
                p.imageUrls?.isNotEmpty == true ? p.imageUrls!.first : null,
          ));
        }
      }
      if (combined.length >= limit) break;
    }

    return combined;
  }

  Future<List<ShopSuggestion>> _fetchShopSuggestions(
      String searchTerm, AppLocalizations? l10n) async {
    try {
      final languageCode = l10n?.localeName ?? 'en';
      final results = await _typesenseManager.shopsService
          .searchShops(
            query: searchTerm,
            hitsPerPage: 5,
            languageCode: languageCode,
          )
          .timeout(const Duration(seconds: 3));

      return results.map((hit) {
        final localizedCategoriesKey = 'categories_$languageCode';
        final categories = hit[localizedCategoriesKey] as List<dynamic>? ??
            hit['categories'] as List<dynamic>? ??
            [];

        return ShopSuggestion(
          id: hit['id']?.toString().replaceAll('shops_', '') ?? '',
          name: hit['name'] ?? '',
          profileImageUrl: hit['profileImageUrl'],
          categories: categories.cast<String>(),
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Shop suggestions error: $e');
      return [];
    }
  }

  Future<List<CategorySuggestion>> _fetchEnhancedCategorySuggestions(
      String searchTerm, AppLocalizations? l10n) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Fetching category suggestions for: "$searchTerm"');
      }

      final rawResults = await _typesenseManager.mainService
          .searchCategories(
            query: searchTerm,
            hitsPerPage: 50,
            languageCode: l10n?.localeName,
          )
          .timeout(const Duration(seconds: 3));

      if (kDebugMode) {
        debugPrint('   Raw Typesense results: ${rawResults.length}');
      }

      final scoredResults = CategorySearchScorer.sortAndLimitResults(
        rawResults,
        searchTerm,
        maxResults: 15,
      );

      if (kDebugMode) {
        debugPrint('   Scored results: ${scoredResults.length}');
      }

      if (scoredResults.isNotEmpty) {
        CategorySearchScorer.debugPrintScores(rawResults, searchTerm);
      }

      return scoredResults;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Category suggestions error: $e');
      return [];
    }
  }

  void _handleError(String message, {bool isNetworkError = false}) {
    if (!mounted) return;
    _suggestions = [];
    _categorySuggestions = [];
    _shopSuggestions = [];
    _isLoading = false;
    _hasNetworkError = isNetworkError;
    _errorMessage = message;
    _resetPagination();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _querySubject.close();
    _autocompleteSubject.close();
    super.dispose();
  }
}

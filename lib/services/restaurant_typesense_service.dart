// lib/services/restaurant_typesense_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';
import '../models/restaurant.dart';
import '../models/food.dart';

// ============================================================================
// PAGE RESULT TYPES
// ============================================================================

class RestaurantSearchPage {
  final List<Restaurant> items;
  final List<String> ids;
  final int page;
  final int nbPages;
  final int total;

  const RestaurantSearchPage({
    required this.items,
    required this.ids,
    required this.page,
    required this.nbPages,
    required this.total,
  });

  static RestaurantSearchPage empty(int page) => RestaurantSearchPage(
        items: [],
        ids: [],
        page: page,
        nbPages: 1,
        total: 0,
      );
}

class FoodSearchPage {
  final List<Food> items;
  final List<String> ids;
  final int page;
  final int nbPages;
  final int total;

  const FoodSearchPage({
    required this.items,
    required this.ids,
    required this.page,
    required this.nbPages,
    required this.total,
  });

  static FoodSearchPage empty(int page) => FoodSearchPage(
        items: [],
        ids: [],
        page: page,
        nbPages: 1,
        total: 0,
      );
}

// ============================================================================
// FACET TYPES
// ============================================================================

class FacetValue {
  final String value;
  final int count;

  const FacetValue({required this.value, required this.count});
}

class RestaurantFacets {
  final List<FacetValue>? cuisineTypes;
  final List<FacetValue>? foodType;
  final List<FacetValue>? workingDays;

  const RestaurantFacets({
    this.cuisineTypes,
    this.foodType,
    this.workingDays,
  });

  static const empty = RestaurantFacets();
}

class FoodFacets {
  final List<FacetValue>? foodCategory;
  final List<FacetValue>? foodType;

  const FoodFacets({this.foodCategory, this.foodType});

  static const empty = FoodFacets();
}

// ============================================================================
// SORT OPTIONS
// ============================================================================

enum RestaurantSortOption {
  ratingDesc,
  ratingAsc,
  nameAsc,
  nameDesc,
  newest,
  defaultSort,
}

enum FoodSortOption {
  priceAsc,
  priceDesc,
  nameAsc,
  newest,
  defaultSort,
}

// ============================================================================
// SERVICE
// ============================================================================

class RestaurantTypesenseService {
  final String _host;
  final String _searchKey;

  Timer? _restaurantDebounceTimer;
  Timer? _foodDebounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  static const _retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(milliseconds: 500),
    randomizationFactor: 0.1,
    maxDelay: Duration(seconds: 2),
  );

  RestaurantTypesenseService({
    required String typesenseHost,
    required String typesenseSearchKey,
  })  : _host = typesenseHost,
        _searchKey = typesenseSearchKey;

  // ── URL & headers ───────────────────────────────────────────────────────

  Uri _searchUri(String collection) =>
      Uri.https(_host, '/collections/$collection/documents/search');

  Map<String, String> get _headers => {
        'X-TYPESENSE-API-KEY': _searchKey,
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache, no-store',
      };

  // ── Sort mappings ───────────────────────────────────────────────────────

  String _restaurantSortBy(RestaurantSortOption sort) {
    switch (sort) {
      case RestaurantSortOption.ratingDesc:
        return 'averageRating:desc';
      case RestaurantSortOption.ratingAsc:
        return 'averageRating:asc';
      case RestaurantSortOption.nameAsc:
        return 'name:asc';
      case RestaurantSortOption.nameDesc:
        return 'name:desc';
      case RestaurantSortOption.newest:
        return 'createdAt:desc';
      case RestaurantSortOption.defaultSort:
        return 'averageRating:desc,createdAt:desc';
    }
  }

  String _foodSortBy(FoodSortOption sort) {
    switch (sort) {
      case FoodSortOption.priceAsc:
        return 'price:asc';
      case FoodSortOption.priceDesc:
        return 'price:desc';
      case FoodSortOption.nameAsc:
        return 'name:asc';
      case FoodSortOption.newest:
        return 'createdAt:desc';
      case FoodSortOption.defaultSort:
        return 'createdAt:desc';
    }
  }

  // ── ID extraction ───────────────────────────────────────────────────────

  String _extractFirestoreId(String typesenseId, String collection) {
    final prefix = '${collection}_';
    return typesenseId.startsWith(prefix)
        ? typesenseId.substring(prefix.length)
        : typesenseId;
  }

  // ── Core fetch ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetchTypesense(
    String collection,
    Map<String, String> params,
  ) async {
    final uri = _searchUri(collection).replace(queryParameters: params);

    return _retryOptions.retry(
      () async {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 5));

        if (response.statusCode >= 500) {
          throw HttpException('Typesense server error: ${response.statusCode}',
              uri: uri);
        }
        if (response.statusCode != 200) {
          debugPrint(
              '[RestaurantTypesense] ${response.statusCode} on $collection: ${response.body}');
          return <String, dynamic>{'hits': [], 'found': 0};
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
      retryIf: (e) =>
          e is SocketException ||
          e is TimeoutException ||
          e is HttpException ||
          e.toString().contains('Failed host lookup'),
    );
  }

  // ── Filter builder ──────────────────────────────────────────────────────

  String? _buildFilterBy(List<String> parts) {
    if (parts.isEmpty) return null;
    return parts.join(' && ');
  }

  // ============================================================================
  // RESTAURANTS
  // ============================================================================

  /// Search restaurants with optional filters and sorting.
  Future<RestaurantSearchPage> searchRestaurants({
    String query = '',
    RestaurantSortOption sort = RestaurantSortOption.defaultSort,
    int page = 0,
    int hitsPerPage = 20,
    List<String>? cuisineTypes,
    List<String>? foodType,
    bool? isActive,
    List<String>? deliveryRegions,
  }) async {
    final filterParts = <String>[];

    if (isActive != null) {
      filterParts.add('isActive:=$isActive');
    }

    if (cuisineTypes != null && cuisineTypes.isNotEmpty) {
      final orParts = cuisineTypes.map((c) => 'cuisineTypes:=$c').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (foodType != null && foodType.isNotEmpty) {
      final orParts = foodType.map((f) => 'foodType:=$f').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (deliveryRegions != null && deliveryRegions.isNotEmpty) {
      final orParts = deliveryRegions.map((r) => 'deliveryRegions:=`$r`').toList();
      orParts.add('deliveryRegions:=`__ALL__`');
      filterParts.add('(${orParts.join(' || ')})');
    }

    final params = <String, String>{
      'q': query.trim().isEmpty ? '*' : query.trim(),
      'query_by': 'name,address',
      'sort_by': _restaurantSortBy(sort),
      'per_page': hitsPerPage.toString(),
      'page': (page + 1).toString(),
      'include_fields':
          'id,name,address,contactNo,profileImageUrl,ownerId,isActive,isBoosted,'
              'latitude,longitude,averageRating,reviewCount,clickCount,followerCount,'
              'foodType,cuisineTypes,workingDays,workingHoursJson,createdAt,minOrderPricesJson',
    };

    final filterBy = _buildFilterBy(filterParts);
    if (filterBy != null) params['filter_by'] = filterBy;
    debugPrint('[RestaurantTypesense] searchRestaurants filter_by: $filterBy');

    try {
      final data = await _fetchTypesense('restaurants', params);
      final rawHits = (data['hits'] as List?) ?? [];
      final found = (data['found'] as num?)?.toInt() ?? 0;

      final ids = <String>[];
      final restaurantItems = <Restaurant>[];

      for (final h in rawHits) {
        final doc = (h as Map)['document'] as Map<String, dynamic>;
        final tsId = (doc['id'] as String?) ?? '';
        final firestoreId = _extractFirestoreId(tsId, 'restaurants');
        ids.add(firestoreId);
        restaurantItems.add(Restaurant.fromMap(doc, id: firestoreId));
      }

      final perPage = hitsPerPage > 0 ? hitsPerPage : 1;
      final nbPages = (found / perPage).ceil().clamp(1, 9999);

      return RestaurantSearchPage(
        items: restaurantItems,
        ids: ids,
        page: page,
        nbPages: nbPages,
        total: found,
      );
    } catch (e) {
      debugPrint('[RestaurantTypesense] searchRestaurants error: $e');
      return RestaurantSearchPage.empty(page);
    }
  }

  /// Debounced version of [searchRestaurants] for search-as-you-type.
  Future<RestaurantSearchPage> debouncedSearchRestaurants({
    String query = '',
    RestaurantSortOption sort = RestaurantSortOption.defaultSort,
    int page = 0,
    int hitsPerPage = 20,
    List<String>? cuisineTypes,
    List<String>? foodType,
    bool? isActive,
  }) {
    _restaurantDebounceTimer?.cancel();
    final completer = Completer<RestaurantSearchPage>();
    _restaurantDebounceTimer = Timer(_debounceDuration, () async {
      try {
        completer.complete(await searchRestaurants(
          query: query,
          sort: sort,
          page: page,
          hitsPerPage: hitsPerPage,
          cuisineTypes: cuisineTypes,
          foodType: foodType,
          isActive: isActive,
        ));
      } catch (e) {
        completer.complete(RestaurantSearchPage.empty(page));
      }
    });
    return completer.future;
  }

  /// Fetch facet counts for restaurant filter UI.
  Future<RestaurantFacets> fetchRestaurantFacets({
    String? query,
    List<String>? cuisineTypes,
    List<String>? foodType,
    List<String>? deliveryRegions,
  }) async {
    final filterParts = <String>['isActive:=true'];

    if (cuisineTypes != null && cuisineTypes.isNotEmpty) {
      final orParts = cuisineTypes.map((c) => 'cuisineTypes:=$c').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (foodType != null && foodType.isNotEmpty) {
      final orParts = foodType.map((f) => 'foodType:=$f').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (deliveryRegions != null && deliveryRegions.isNotEmpty) {
      final orParts =
          deliveryRegions.map((r) => 'deliveryRegions:=`$r`').toList();
      orParts.add('deliveryRegions:=`__ALL__`');
      filterParts.add('(${orParts.join(' || ')})');
    }

    final params = <String, String>{
      'q': query?.trim().isEmpty ?? true ? '*' : query!.trim(),
      'query_by': 'name,address',
      'per_page': '0',
      'facet_by': 'cuisineTypes,foodType,workingDays',
      'max_facet_values': '50',
    };

    final filterBy = _buildFilterBy(filterParts);
    if (filterBy != null) params['filter_by'] = filterBy;

    try {
      final data = await _fetchTypesense('restaurants', params);
      final facetCounts = (data['facet_counts'] as List?) ?? [];

      List<FacetValue>? parsedCuisineTypes;
      List<FacetValue>? parsedFoodType;
      List<FacetValue>? parsedWorkingDays;

      for (final facet in facetCounts) {
        final fieldName = (facet as Map)['field_name'] as String? ?? '';
        final counts = _parseFacetCounts(facet['counts'] as List?);
        if (counts.isEmpty) continue;

        switch (fieldName) {
          case 'cuisineTypes':
            parsedCuisineTypes = counts;
            break;
          case 'foodType':
            parsedFoodType = counts;
            break;
          case 'workingDays':
            parsedWorkingDays = counts;
            break;
        }
      }

      return RestaurantFacets(
        cuisineTypes: parsedCuisineTypes,
        foodType: parsedFoodType,
        workingDays: parsedWorkingDays,
      );
    } catch (e) {
      debugPrint('[RestaurantTypesense] fetchRestaurantFacets error: $e');
      return RestaurantFacets.empty;
    }
  }

  // ============================================================================
  // FOODS
  // ============================================================================

  /// Search foods with optional filters.
  Future<FoodSearchPage> searchFoods({
    String query = '',
    FoodSortOption sort = FoodSortOption.defaultSort,
    int page = 0,
    int hitsPerPage = 20,
    String? restaurantId,
    List<String>? foodCategory,
    List<String>? foodType,
    bool? isAvailable,
    double? minPrice,
    double? maxPrice,
  }) async {
    final filterParts = <String>[];

    if (restaurantId != null && restaurantId.isNotEmpty) {
      filterParts.add('restaurantId:=$restaurantId');
    }

    if (isAvailable != null) {
      filterParts.add('isAvailable:=$isAvailable');
    }

    if (foodCategory != null && foodCategory.isNotEmpty) {
      final orParts = foodCategory.map((c) => 'foodCategory:=$c').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (foodType != null && foodType.isNotEmpty) {
      final orParts = foodType.map((f) => 'foodType:=$f').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (minPrice != null) filterParts.add('price:>=$minPrice');
    if (maxPrice != null) filterParts.add('price:<=$maxPrice');

    final params = <String, String>{
      'q': query.trim().isEmpty ? '*' : query.trim(),
      'query_by': 'name,description,foodCategory,foodType',
      'sort_by': _foodSortBy(sort),
      'per_page': hitsPerPage.toString(),
      'page': (page + 1).toString(),
      'include_fields':
          'id,name,description,price,foodCategory,foodType,imageUrl,'
              'isAvailable,preparationTime,restaurantId,extras,createdAt',
    };

    final filterBy = _buildFilterBy(filterParts);
    if (filterBy != null) params['filter_by'] = filterBy;

    try {
      final data = await _fetchTypesense('foods', params);
      final rawHits = (data['hits'] as List?) ?? [];
      final found = (data['found'] as num?)?.toInt() ?? 0;

      final ids = <String>[];
      final foodItems = <Food>[];

      for (final h in rawHits) {
        final doc = (h as Map)['document'] as Map<String, dynamic>;
        final tsId = (doc['id'] as String?) ?? '';
        final firestoreId = _extractFirestoreId(tsId, 'foods');
        ids.add(firestoreId);
        foodItems.add(Food.fromMap(doc, id: firestoreId));
      }

      final perPage = hitsPerPage > 0 ? hitsPerPage : 1;
      final nbPages = (found / perPage).ceil().clamp(1, 9999);

      return FoodSearchPage(
        items: foodItems,
        ids: ids,
        page: page,
        nbPages: nbPages,
        total: found,
      );
    } catch (e) {
      debugPrint('[RestaurantTypesense] searchFoods error: $e');
      return FoodSearchPage.empty(page);
    }
  }

  /// Debounced version of [searchFoods] for search-as-you-type.
  Future<FoodSearchPage> debouncedSearchFoods({
    String query = '',
    FoodSortOption sort = FoodSortOption.defaultSort,
    int page = 0,
    int hitsPerPage = 20,
    String? restaurantId,
    List<String>? foodCategory,
    List<String>? foodType,
    bool? isAvailable,
    double? minPrice,
    double? maxPrice,
  }) {
    _foodDebounceTimer?.cancel();
    final completer = Completer<FoodSearchPage>();
    _foodDebounceTimer = Timer(_debounceDuration, () async {
      try {
        completer.complete(await searchFoods(
          query: query,
          sort: sort,
          page: page,
          hitsPerPage: hitsPerPage,
          restaurantId: restaurantId,
          foodCategory: foodCategory,
          foodType: foodType,
          isAvailable: isAvailable,
          minPrice: minPrice,
          maxPrice: maxPrice,
        ));
      } catch (e) {
        completer.complete(FoodSearchPage.empty(page));
      }
    });
    return completer.future;
  }

  /// Fetch facet counts for food filter UI.
  Future<FoodFacets> fetchFoodFacets({
    String? query,
    String? restaurantId,
    List<String>? foodCategory,
    List<String>? foodType,
  }) async {
    final filterParts = <String>['isAvailable:=true'];

    if (restaurantId != null && restaurantId.isNotEmpty) {
      filterParts.add('restaurantId:=$restaurantId');
    }

    if (foodCategory != null && foodCategory.isNotEmpty) {
      final orParts = foodCategory.map((c) => 'foodCategory:=$c').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    if (foodType != null && foodType.isNotEmpty) {
      final orParts = foodType.map((f) => 'foodType:=$f').toList();
      filterParts.add(
          orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})');
    }

    final params = <String, String>{
      'q': query?.trim().isEmpty ?? true ? '*' : query!.trim(),
      'query_by': 'name,description,foodCategory,foodType',
      'per_page': '0',
      'facet_by': 'foodCategory,foodType',
      'max_facet_values': '50',
    };

    final filterBy = _buildFilterBy(filterParts);
    if (filterBy != null) params['filter_by'] = filterBy;

    try {
      final data = await _fetchTypesense('foods', params);
      final facetCounts = (data['facet_counts'] as List?) ?? [];

      List<FacetValue>? parsedFoodCategory;
      List<FacetValue>? parsedFoodType;

      for (final facet in facetCounts) {
        final fieldName = (facet as Map)['field_name'] as String? ?? '';
        final counts = _parseFacetCounts(facet['counts'] as List?);
        if (counts.isEmpty) continue;

        switch (fieldName) {
          case 'foodCategory':
            parsedFoodCategory = counts;
            break;
          case 'foodType':
            parsedFoodType = counts;
            break;
        }
      }

      return FoodFacets(
        foodCategory: parsedFoodCategory,
        foodType: parsedFoodType,
      );
    } catch (e) {
      debugPrint('[RestaurantTypesense] fetchFoodFacets error: $e');
      return FoodFacets.empty;
    }
  }

  // ============================================================================
  // HEALTH CHECK
  // ============================================================================

  Future<bool> isServiceReachable() async {
    try {
      final uri = _searchUri('restaurants').replace(queryParameters: {
        'q': '*',
        'query_by': 'name',
        'per_page': '1',
      });
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (e) {
      debugPrint('[RestaurantTypesense] unreachable: $e');
      return false;
    }
  }

  // ============================================================================
  // PRIVATE HELPERS
  // ============================================================================

  List<FacetValue> _parseFacetCounts(List<dynamic>? counts) {
    if (counts == null) return [];
    return counts
        .map((c) {
          final value = (c as Map)['value']?.toString() ?? '';
          final count = (c['count'] as num?)?.toInt() ?? 0;
          return FacetValue(value: value, count: count);
        })
        .where((fv) => fv.value.isNotEmpty && fv.count > 0)
        .toList();
  }

  void dispose() {
    _restaurantDebounceTimer?.cancel();
    _foodDebounceTimer?.cancel();
  }
}

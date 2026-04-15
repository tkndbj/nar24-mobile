// lib/services/market_typesense_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:retry/retry.dart';

// ============================================================================
// MODELS
// ============================================================================

class MarketItem {
  final String id;
  final String name;
  final String brand;
  final String type;
  final String category;
  final double price;
  final int stock;
  final String description;
  final String imageUrl;
  final List<String> imageUrls;
  final bool isAvailable;
  final int? createdAt;

  const MarketItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.type,
    required this.category,
    required this.price,
    required this.stock,
    this.description = '',
    this.imageUrl = '',
    this.imageUrls = const [],
    this.isAvailable = true,
    this.createdAt,
  });

  factory MarketItem.fromTypesense(Map<String, dynamic> doc,
      {required String id}) {
    return MarketItem(
      id: id,
      name: (doc['name'] as String?) ?? '',
      brand: (doc['brand'] as String?) ?? '',
      type: (doc['type'] as String?) ?? '',
      category: (doc['category'] as String?) ?? '',
      price: (doc['price'] as num?)?.toDouble() ?? 0.0,
      stock: (doc['stock'] as num?)?.toInt() ?? 0,
      description: (doc['description'] as String?) ?? '',
      imageUrl: (doc['imageUrl'] as String?) ?? '',
      imageUrls: (doc['imageUrls'] as List?)?.cast<String>() ?? [],
      isAvailable: (doc['isAvailable'] as bool?) ?? true,
      createdAt: (doc['createdAt'] as num?)?.toInt(),
    );
  }
}

// ============================================================================
// PAGE RESULT
// ============================================================================

class MarketSearchPage {
  final List<MarketItem> items;
  final int page;
  final int nbPages;
  final int total;

  const MarketSearchPage({
    required this.items,
    required this.page,
    required this.nbPages,
    required this.total,
  });

  static MarketSearchPage empty(int page) => MarketSearchPage(
        items: [],
        page: page,
        nbPages: 1,
        total: 0,
      );
}

// ============================================================================
// FACET TYPES
// ============================================================================

class MarketFacetValue {
  final String value;
  final int count;

  const MarketFacetValue({required this.value, required this.count});
}

class MarketFacets {
  final List<MarketFacetValue> brands;
  final List<MarketFacetValue> types;

  const MarketFacets({
    this.brands = const [],
    this.types = const [],
  });

  static const empty = MarketFacets();
}

// ============================================================================
// SORT OPTIONS
// ============================================================================

enum MarketSortOption {
  newest,
  priceAsc,
  priceDesc,
  nameAsc,
}

// ============================================================================
// SERVICE
// ============================================================================

class MarketTypesenseService {
  final String _host;
  final String _searchKey;

  static const _collection = 'market_items';

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  static const _retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(milliseconds: 500),
    randomizationFactor: 0.1,
    maxDelay: Duration(seconds: 2),
  );

  late final http.Client _client = _buildClient();

  MarketTypesenseService({
    required String typesenseHost,
    required String typesenseSearchKey,
  })  : _host = typesenseHost,
        _searchKey = typesenseSearchKey;

  // ── HTTP ────────────────────────────────────────────────────────────────

  static http.Client _buildClient() {
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        return host.endsWith('.typesense.net');
      };
    return IOClient(inner);
  }

  Uri _searchUri() =>
      Uri.https(_host, '/collections/$_collection/documents/search');

  Map<String, String> get _headers => {
        'X-TYPESENSE-API-KEY': _searchKey,
        'Content-Type': 'application/json',
      };

  // ── Sort ────────────────────────────────────────────────────────────────

  String _sortBy(MarketSortOption sort) {
    switch (sort) {
      case MarketSortOption.newest:
        return 'createdAt:desc';
      case MarketSortOption.priceAsc:
        return 'price:asc';
      case MarketSortOption.priceDesc:
        return 'price:desc';
      case MarketSortOption.nameAsc:
        return 'name:asc';
    }
  }

  // ── Core fetch ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetch(Map<String, String> params) async {
    final uri = _searchUri().replace(queryParameters: params);

    return await _retryOptions.retry(
      () async {
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 5));

        if (response.statusCode >= 500) {
          throw HttpException(
            'Typesense server error: ${response.statusCode}',
            uri: uri,
          );
        }
        if (response.statusCode != 200) {
          debugPrint(
              '[MarketTypesense] ${response.statusCode}: ${response.body}');
          return <String, dynamic>{'hits': [], 'found': 0};
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
      retryIf: (e) =>
          e is SocketException ||
          e is TimeoutException ||
          e is HttpException ||
          e is HandshakeException ||
          e.toString().contains('Failed host lookup'),
    );
  }

  // ── ID extraction ───────────────────────────────────────────────────────

  String _extractId(String typesenseId) {
    const prefix = '${_collection}_';
    return typesenseId.startsWith(prefix)
        ? typesenseId.substring(prefix.length)
        : typesenseId;
  }

  // ============================================================================
  // SEARCH
  // ============================================================================

  /// Search market items with category filter, brand/type facet filters,
  /// and pagination.
  Future<MarketSearchPage> searchItems({
    String query = '',
    required String category,
    MarketSortOption sort = MarketSortOption.newest,
    int page = 0,
    int hitsPerPage = 20,
    List<String>? brands,
    List<String>? types,
  }) async {
    final filterParts = <String>[
      'isAvailable:=true',
      'category:=$category',
    ];

    if (brands != null && brands.isNotEmpty) {
      final orParts = brands.map((b) => 'brand:=`$b`').toList();
      filterParts.add(
        orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})',
      );
    }

    if (types != null && types.isNotEmpty) {
      final orParts = types.map((t) => 'type:=`$t`').toList();
      filterParts.add(
        orParts.length == 1 ? orParts.first : '(${orParts.join(' || ')})',
      );
    }

    final params = <String, String>{
      'q': query.trim().isEmpty ? '*' : query.trim(),
      'query_by': 'name,brand,type,description',
      'sort_by': _sortBy(sort),
      'per_page': hitsPerPage.toString(),
      'page': (page + 1).toString(),
      'filter_by': filterParts.join(' && '),
      'include_fields':
          'id,name,brand,type,category,price,stock,description,imageUrl,imageUrls,isAvailable,createdAt',
    };

    try {
      final data = await _fetch(params);
      final rawHits = (data['hits'] as List?) ?? [];
      final found = (data['found'] as num?)?.toInt() ?? 0;

      final items = <MarketItem>[];
      for (final h in rawHits) {
        final doc = (h as Map)['document'] as Map<String, dynamic>;
        final tsId = (doc['id'] as String?) ?? '';
        final firestoreId = _extractId(tsId);
        items.add(MarketItem.fromTypesense(doc, id: firestoreId));
      }

      final perPage = hitsPerPage > 0 ? hitsPerPage : 1;
      final nbPages = (found / perPage).ceil().clamp(1, 9999);

      return MarketSearchPage(
        items: items,
        page: page,
        nbPages: nbPages,
        total: found,
      );
    } catch (e) {
      debugPrint('[MarketTypesense] searchItems error: $e');
      return MarketSearchPage.empty(page);
    }
  }

  /// Debounced version of [searchItems] for search-as-you-type.
  Future<MarketSearchPage> debouncedSearchItems({
    String query = '',
    required String category,
    MarketSortOption sort = MarketSortOption.newest,
    int page = 0,
    int hitsPerPage = 20,
    List<String>? brands,
    List<String>? types,
  }) {
    _debounceTimer?.cancel();
    final completer = Completer<MarketSearchPage>();
    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        completer.complete(await searchItems(
          query: query,
          category: category,
          sort: sort,
          page: page,
          hitsPerPage: hitsPerPage,
          brands: brands,
          types: types,
        ));
      } catch (e) {
        completer.complete(MarketSearchPage.empty(page));
      }
    });
    return completer.future;
  }

  // ============================================================================
  // FACETS (disjunctive)
  // ============================================================================

  /// Fetch brand and type facets for a given category.
  ///
  /// Uses disjunctive faceting: selecting a brand doesn't collapse
  /// the type facets, and vice versa.
  /// Sends 3 queries in one multi_search request:
  ///   0. Main — all filters → items count
  ///   1. Brand facets — all filters EXCEPT brand → correct brand counts
  ///   2. Type facets — all filters EXCEPT type → correct type counts
  Future<MarketFacets> fetchFacets({
    required String category,
    String query = '',
    List<String>? selectedBrands,
    List<String>? selectedTypes,
  }) async {
    final baseFilter = 'isAvailable:=true && category:=$category';

    String? brandFilter;
    if (selectedBrands != null && selectedBrands.isNotEmpty) {
      final parts = selectedBrands.map((b) => 'brand:=`$b`').toList();
      brandFilter = parts.length == 1 ? parts.first : '(${parts.join(' || ')})';
    }

    String? typeFilter;
    if (selectedTypes != null && selectedTypes.isNotEmpty) {
      final parts = selectedTypes.map((t) => 'type:=`$t`').toList();
      typeFilter = parts.length == 1 ? parts.first : '(${parts.join(' || ')})';
    }

    final q = query.trim().isEmpty ? '*' : query.trim();
    const queryBy = 'name,brand,type,description';

    final searches = <Map<String, dynamic>>[
      // 0: Main query (no hits needed, just total count)
      {
        'q': q,
        'query_by': queryBy,
        'per_page': 0,
        'filter_by': [
          baseFilter,
          if (brandFilter != null) brandFilter,
          if (typeFilter != null) typeFilter,
        ].join(' && '),
      },
      // 1: Brand facets — exclude brand filter
      {
        'q': q,
        'query_by': queryBy,
        'per_page': 0,
        'facet_by': 'brand',
        'max_facet_values': 100,
        'filter_by': [
          baseFilter,
          if (typeFilter != null) typeFilter,
        ].join(' && '),
      },
      // 2: Type facets — exclude type filter
      {
        'q': q,
        'query_by': queryBy,
        'per_page': 0,
        'facet_by': 'type',
        'max_facet_values': 100,
        'filter_by': [
          baseFilter,
          if (brandFilter != null) brandFilter,
        ].join(' && '),
      },
    ];

    try {
      final uri = Uri.https(_host, '/multi_search')
          .replace(queryParameters: {'collection': _collection});

      final resp = await _retryOptions.retry(
        () async {
          final r = await _client
              .post(uri,
                  headers: _headers, body: jsonEncode({'searches': searches}))
              .timeout(const Duration(seconds: 6));
          if (r.statusCode >= 500) {
            throw HttpException('Typesense multi_search 5xx: ${r.statusCode}',
                uri: uri);
          }
          return r;
        },
        retryIf: (e) =>
            e is SocketException ||
            e is TimeoutException ||
            e is HttpException ||
            e.toString().contains('Failed host lookup'),
      );

      if (resp.statusCode != 200) {
        debugPrint('[MarketTypesense] facets error ${resp.statusCode}');
        return MarketFacets.empty;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];

      // Parse brand facets from result[1]
      final brandFacets = <MarketFacetValue>[];
      if (results.length > 1) {
        final facetCounts = (results[1] as Map)['facet_counts'] as List? ?? [];
        for (final facet in facetCounts) {
          if ((facet as Map)['field_name'] == 'brand') {
            brandFacets.addAll(_parseFacets(facet['counts'] as List?));
          }
        }
      }

      // Parse type facets from result[2]
      final typeFacets = <MarketFacetValue>[];
      if (results.length > 2) {
        final facetCounts = (results[2] as Map)['facet_counts'] as List? ?? [];
        for (final facet in facetCounts) {
          if ((facet as Map)['field_name'] == 'type') {
            typeFacets.addAll(_parseFacets(facet['counts'] as List?));
          }
        }
      }

      return MarketFacets(brands: brandFacets, types: typeFacets);
    } catch (e) {
      debugPrint('[MarketTypesense] fetchFacets error: $e');
      return MarketFacets.empty;
    }
  }

  // ============================================================================
  // HEALTH CHECK
  // ============================================================================

  Future<bool> isServiceReachable() async {
    try {
      final uri = _searchUri().replace(queryParameters: {
        'q': '*',
        'query_by': 'name',
        'per_page': '1',
      });
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (e) {
      debugPrint('[MarketTypesense] unreachable: $e');
      return false;
    }
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  List<MarketFacetValue> _parseFacets(List<dynamic>? counts) {
    if (counts == null) return [];
    return counts
        .map((c) {
          final value = (c as Map)['value']?.toString() ?? '';
          final count = (c['count'] as num?)?.toInt() ?? 0;
          return MarketFacetValue(value: value, count: count);
        })
        .where((fv) => fv.value.isNotEmpty && fv.count > 0)
        .toList();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _client.close();
  }
}

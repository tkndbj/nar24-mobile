import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';
import '../models/product.dart';
import '../models/product_summary.dart';
import '../models/category_suggestion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/io_client.dart';

class TypeSensePage {
  final List<String> ids;
  final List<Map<String, dynamic>> hits;
  final int page;
  final int nbPages;
  final int totalFound;
  final Map<String, List<Map<String, dynamic>>> facets;
  TypeSensePage({
    required this.ids,
    required this.hits,
    required this.page,
    required this.nbPages,
    this.totalFound = 0,
    this.facets = const {},
  });

}

class TypeSenseService {
  final String applicationId; // unused – kept for API compatibility
  final String apiKey; // unused – kept for API compatibility
  final String mainIndexName;
  final String categoryIndexName; // unused – kept for API compatibility

  // Typesense connection details – set in TypesenseServiceManager
  final String _host;
  final String _searchKey;
  late final http.Client _client;

  TypeSenseService({
    required this.applicationId,
    required this.apiKey,
    required this.mainIndexName,
    required this.categoryIndexName,
    required String typesenseHost,
    required String typesenseSearchKey,
  })  : _host = typesenseHost,
        _searchKey = typesenseSearchKey {
    // Scoped SSL bypass for old Android devices that don't trust
    // newer root CAs. Strictly limited to *.typesense.net.
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        return host.endsWith('.typesense.net');
      };
    _client = IOClient(inner);
  }

  Timer? _productDebounceTimer;
  final Duration _debounceDuration = const Duration(milliseconds: 300);

  static const RetryOptions _retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(milliseconds: 500),
    randomizationFactor: 0.1,
    maxDelay: Duration(seconds: 2),
  );

  // ── Helpers ────────────────────────────────────────────────────────────────

  Uri _searchUri(String collection) =>
      Uri.https(_host, '/collections/$collection/documents/search');

  Map<String, String> get _headers => {
        'X-TYPESENSE-API-KEY': _searchKey,
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache, no-store',
      };

  /// Convert TypeSense sort option → Typesense sort_by string
  String _sortBy(String sortOption) {
    switch (sortOption) {
      case 'date':
        return 'createdAt:desc';
      case 'alphabetical':
        return 'productName:asc';
      case 'price_asc':
        return 'price:asc';
      case 'price_desc':
        return 'price:desc';
      case 'timestamp':
        return 'timestampForSorting:desc';
      default:
        return 'promotionScore:desc,createdAt:desc';
    }
  }

  String? _buildFilterBy(List<String>? filters) {
    if (filters == null || filters.isEmpty) return null;
    return filters
        .map((f) {
          // e.g. 'shopId:"abc123"'  →  'shopId:=abc123'
          final parts = f.split(':');
          if (parts.length < 2) return null;
          final field = parts[0].trim();
          final value = parts.sublist(1).join(':').trim().replaceAll('"', '');
          return '$field:=$value';
        })
        .whereType<String>()
        .join(' && ');
  }

  String _extractFirestoreId(String typesenseId, String collection) {
    final prefix = '${collection}_';
    if (typesenseId.startsWith(prefix)) {
      return typesenseId.substring(prefix.length);
    }
    return typesenseId;
  }

  // ── Core search ────────────────────────────────────────────────────────────

  Future<List<T>> _searchInIndex<T>({
    required String collection,
    required String query,
    required String sortOption,
    required T Function(Map<String, dynamic>) mapper,
    int page = 0,
    int hitsPerPage = 50,
    List<String>? filters,
    String queryBy =
        'productName,brandModel,sellerName,category_en,category_tr,category_ru,subcategory_en,subcategory_tr,subcategory_ru,subsubcategory_en,subsubcategory_tr,subsubcategory_ru',
  }) async {
    final uri = _searchUri(collection);
    final filterBy = _buildFilterBy(filters);

    final params = <String, String>{
      'q': query.isEmpty ? '*' : query,
      'query_by': queryBy,
      'sort_by': _sortBy(sortOption),
      'per_page': hitsPerPage.toString(),
      'page': (page + 1).toString(), // Typesense pages start at 1
    };
    if (filterBy != null) params['filter_by'] = filterBy;

    return await _retryOptions.retry(
      () async {
        try {
          final response = await _client
              .get(uri.replace(queryParameters: params), headers: _headers)
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final hits = (data['hits'] as List?) ?? [];
            return hits.map((h) {
              final doc = Map<String, dynamic>.from((h
                  as Map<String, dynamic>)['document'] as Map<String, dynamic>);
              doc['objectID'] = doc['id'];
              return mapper(doc);
            }).toList();
          } else if (response.statusCode >= 500) {
            throw HttpException(
                'Typesense server error: ${response.statusCode}',
                uri: uri);
          } else {
            return <T>[];
          }
        } on SocketException catch (e) {
          throw e;
        } on TimeoutException catch (e) {
          throw e;
        } on FormatException {
          return <T>[];
        }
      },
      retryIf: (e) =>
          e is SocketException ||
          e is TimeoutException ||
          e is HttpException ||
          e.toString().contains('Failed host lookup'),
    );
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<List<ProductSummary>> searchProducts({
    required String query,
    required String sortOption,
    int page = 0,
    int hitsPerPage = 50,
    List<String>? filters,
  }) async {
    try {
      return await _searchInIndex<ProductSummary>(
        collection: mainIndexName,
        query: query,
        sortOption: sortOption,
        mapper: (doc) => ProductSummary.fromTypeSense(doc),
        page: page,
        hitsPerPage: hitsPerPage,
        filters: filters,
      );
    } catch (e) {
      debugPrint('Typesense searchProducts error: $e');
      return [];
    }
  }

  Future<List<ProductSummary>> debouncedSearchProducts({
    required String query,
    required String sortOption,
    int page = 0,
    int hitsPerPage = 50,
    List<String>? filters,
  }) {
    _productDebounceTimer?.cancel();
    final completer = Completer<List<ProductSummary>>();
    _productDebounceTimer = Timer(_debounceDuration, () async {
      try {
        completer.complete(await searchProducts(
          query: query,
          sortOption: sortOption,
          page: page,
          hitsPerPage: hitsPerPage,
          filters: filters,
        ));
      } catch (e) {
        completer.complete([]);
      }
    });
    return completer.future;
  }

  Future<List<Product>> searchShopProducts({
    required String shopId,
    required String query,
    required String sortOption,
    int page = 0,
    int hitsPerPage = 100,
    List<String>? additionalFilters,
  }) async {
    try {
      final filters = ['shopId:"$shopId"', ...?additionalFilters];
      return await _searchInIndex<Product>(
        collection: 'shop_products',
        query: query,
        sortOption: sortOption,
        mapper: (doc) => Product.fromTypeSense(doc),
        page: page,
        hitsPerPage: hitsPerPage,
        filters: filters,
      );
    } catch (e) {
      debugPrint('Typesense searchShopProducts error: $e');
      return [];
    }
  }

  Future<List<Product>> debouncedSearchShopProducts({
    required String shopId,
    required String query,
    required String sortOption,
    int page = 0,
    int hitsPerPage = 100,
    List<String>? additionalFilters,
  }) {
    _productDebounceTimer?.cancel();
    final completer = Completer<List<Product>>();
    _productDebounceTimer = Timer(_debounceDuration, () async {
      try {
        completer.complete(await searchShopProducts(
          shopId: shopId,
          query: query,
          sortOption: sortOption,
          page: page,
          hitsPerPage: hitsPerPage,
          additionalFilters: additionalFilters,
        ));
      } catch (e) {
        completer.complete([]);
      }
    });
    return completer.future;
  }

  Future<List<Map<String, dynamic>>> searchShops({
    required String query,
    int page = 0,
    int hitsPerPage = 10,
    String? languageCode,
  }) async {
    try {
      final uri = _searchUri('shops');
      final params = <String, String>{
        'q': query.isEmpty ? '*' : query,
        'query_by': 'name,searchableText',
        'per_page': hitsPerPage.toString(),
        'page': (page + 1).toString(),
      };

      return await _retryOptions.retry(() async {
        final response = await _client
            .get(uri.replace(queryParameters: params), headers: _headers)
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final hits = (data['hits'] as List?) ?? [];
          return hits
              .map((h) => (h as Map<String, dynamic>)['document']
                  as Map<String, dynamic>)
              .toList();
        } else if (response.statusCode >= 500) {
          throw HttpException('Typesense server error: ${response.statusCode}',
              uri: uri);
        }
        return <Map<String, dynamic>>[];
      },
          retryIf: (e) =>
              e is SocketException ||
              e is TimeoutException ||
              e is HttpException);
    } catch (e) {
      debugPrint('Typesense searchShops error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchOrdersInTypeSense({
    required String query,
    required String userId,
    required bool isSold,
    int page = 0,
    int hitsPerPage = 20,
  }) async {
    try {
      final uri = _searchUri('orders');
      final userField = isSold ? 'sellerId' : 'buyerId';
      final params = <String, String>{
        'q': query.isEmpty ? '*' : query,
        'query_by': 'searchableText,productName,buyerName,sellerName',
        'filter_by': '$userField:=$userId',
        'per_page': hitsPerPage.toString(),
        'page': (page + 1).toString(),
      };

      final response = await _client
          .get(uri.replace(queryParameters: params), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final hits = (data['hits'] as List?) ?? [];
        return hits
            .map((h) =>
                (h as Map<String, dynamic>)['document'] as Map<String, dynamic>)
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Typesense searchOrders error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchOrdersByShopId({
    required String query,
    required String shopId,
    int page = 0,
    int hitsPerPage = 20,
  }) async {
    try {
      final uri = _searchUri('orders');
      final params = <String, String>{
        'q': query.isEmpty ? '*' : query,
        'query_by': 'searchableText,productName,buyerName,sellerName',
        'filter_by': 'shopId:=$shopId',
        'per_page': hitsPerPage.toString(),
        'page': (page + 1).toString(),
      };

      final response = await _client
          .get(uri.replace(queryParameters: params), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final hits = (data['hits'] as List?) ?? [];
        return hits
            .map((h) =>
                (h as Map<String, dynamic>)['document'] as Map<String, dynamic>)
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Typesense searchOrdersByShopId error: $e');
      return [];
    }
  }

  Future<TypeSensePage> searchIdsWithFacets({
    required String indexName,
    String query = '',
    int page = 0,
    int hitsPerPage = 20,
    List<List<String>>? facetFilters,
    List<String>? numericFilters,
    String sortOption = 'date',
    String? additionalFilterBy,
    String? queryBy,
    String? includeFields,
    String? facetBy,
    int maxFacetValues = 100,
  }) async {
    final uri = _searchUri(indexName);

    final filterParts = <String>[];

    if (additionalFilterBy != null && additionalFilterBy.isNotEmpty) {
      filterParts.add(additionalFilterBy);
    }

    if (facetFilters != null) {
      for (final group in facetFilters) {
        if (group.isEmpty) continue;
        final orParts = group
            .map((f) {
              final colon = f.indexOf(':');
              if (colon < 0) return null;
              final field = f.substring(0, colon).trim();
              final value = f.substring(colon + 1).trim().replaceAll('"', '');
              return '$field:=$value';
            })
            .whereType<String>()
            .toList();

        if (orParts.length == 1) {
          filterParts.add(orParts.first);
        } else if (orParts.length > 1) {
          filterParts.add('(${orParts.join(' || ')})');
        }
      }
    }

    if (numericFilters != null) {
      for (final nf in numericFilters) {
        final converted = nf
            .replaceAllMapped(
              RegExp(r'(\w+)\s*(>=|<=|>|<|=)\s*(\S+)'),
              (m) => '${m[1]}:${m[2]}${m[3]}',
            )
            .trim();
        if (converted.isNotEmpty) filterParts.add(converted);
      }
    }

    final params = <String, String>{
      'q': query.isEmpty ? '*' : query,
      'query_by': queryBy ??
          'productName,brandModel,sellerName,category_en,category_tr,category_ru,subcategory_en,subcategory_tr,subcategory_ru,subsubcategory_en,subsubcategory_tr,subsubcategory_ru',
      'sort_by': _sortBy(sortOption),
      'per_page': hitsPerPage.toString(),
      'page': (page + 1).toString(),
    };

    if (includeFields != null) {
      params['include_fields'] = includeFields;
    } else {
      params['include_fields'] =
          'id,productName,price,originalPrice,discountPercentage,brandModel,'
          'category,subcategory,subsubcategory,gender,availableColors,colorImagesJson,colorQuantitiesJson,'
          'shopId,ownerId,userId,promotionScore,createdAt,imageUrls,'
          'sellerName,condition,currency,quantity,averageRating,reviewCount,'
          'isBoosted,isFeatured,purchaseCount,bestSellerRank,deliveryOption,paused,'
          'bundleIds,videoUrl,campaignName,discountThreshold,bulkDiscountPercentage';
    }

    if (facetBy != null && facetBy.isNotEmpty) {
      params['facet_by'] = facetBy;
      params['max_facet_values'] = maxFacetValues.toString();
    }

    if (filterParts.isNotEmpty) {
      params['filter_by'] = filterParts.join(' && ');
    }

    debugPrint(
        'Typesense request for $indexName: filter_by=${params['filter_by']}');

    try {
      final resp = await _retryOptions.retry(
        () async {
          final r = await _client
              .get(uri.replace(queryParameters: params), headers: _headers)
              .timeout(const Duration(seconds: 5));
          if (r.statusCode >= 500) {
            throw HttpException('Typesense 5xx: ${r.statusCode}', uri: uri);
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
        debugPrint('Typesense error ${resp.statusCode}: ${resp.body}');
        return TypeSensePage(
            ids: const [], hits: const [], page: page, nbPages: page + 1);
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final hits = (data['hits'] as List?) ?? [];
      final found = (data['found'] as int?) ?? 0;

      debugPrint('Typesense returned ${hits.length} hits (found=$found)');

      final ids = <String>[];
      final hitDocs = <Map<String, dynamic>>[];

      for (final h in hits) {
        final doc = Map<String, dynamic>.from((h as Map)['document'] as Map);
        doc['objectID'] = doc['id'];
        hitDocs.add(doc);

        final typesenseId = (doc['id'] ?? '').toString();
        final firestoreId = _extractFirestoreId(typesenseId, indexName);
        if (firestoreId.isNotEmpty) {
          ids.add(firestoreId);
        }
      }

      final perPage = hitsPerPage > 0 ? hitsPerPage : 1;
      final totalPages = (found / perPage).ceil().clamp(1, 9999);

      // Parse facet counts if facet_by was requested
      final parsedFacets = <String, List<Map<String, dynamic>>>{};
      if (facetBy != null) {
        final facetCounts = data['facet_counts'] as List? ?? [];
        for (final facet in facetCounts) {
          final fieldName = facet['field_name'] as String? ?? '';
          final counts = (facet['counts'] as List? ?? [])
              .map((c) => {
                    'value': (c as Map)['value']?.toString() ?? '',
                    'count': (c['count'] as num?)?.toInt() ?? 0,
                  })
              .where((c) =>
                  c['value'].toString().isNotEmpty && (c['count'] as int) > 0)
              .toList();
          if (counts.isNotEmpty) {
            parsedFacets[fieldName] = counts;
          }
        }
      }

      return TypeSensePage(
          ids: ids, hits: hitDocs, page: page, nbPages: totalPages,
          totalFound: found, facets: parsedFacets);
    } catch (e) {
      debugPrint('Typesense exception: $e');
      return TypeSensePage(
          ids: const [], hits: const [], page: page, nbPages: page + 1);
    }
  }

  Future<List<CategorySuggestion>> searchCategories({
    required String query,
    int hitsPerPage = 10,
    String? languageCode,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final lang = languageCode ?? 'en';
      final uri = _searchUri(mainIndexName);

      // Search primarily against category fields to find relevant categories.
      // Also include productName so that e.g. "Nike" finds the categories
      // those products belong to.
      final params = <String, String>{
        'q': query.trim(),
        'query_by': 'category_$lang,subcategory_$lang,subsubcategory_$lang,'
            'category_en,subcategory_en,subsubcategory_en,'
            'productName',
        'per_page': '50', // over-fetch to get diverse categories
        'include_fields': 'category,subcategory,subsubcategory,'
            'category_en,category_tr,category_ru,'
            'subcategory_en,subcategory_tr,subcategory_ru,'
            'subsubcategory_en,subsubcategory_tr,subsubcategory_ru',
      };

      final response = await _client
          .get(uri.replace(queryParameters: params), headers: _headers)
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final hits = (data['hits'] as List?) ?? [];

      final seen = <String>{};
      final results = <CategorySuggestion>[];

      for (final h in hits) {
        final doc =
            (h as Map<String, dynamic>)['document'] as Map<String, dynamic>?;
        if (doc == null) continue;

        final category = doc['category']?.toString() ?? '';
        final subcategory = doc['subcategory']?.toString() ?? '';
        final subsubcategory = doc['subsubcategory']?.toString() ?? '';

        // Localized display names
        final catDisplay = doc['category_$lang']?.toString() ??
            doc['category_en']?.toString() ??
            category;
        final subDisplay = doc['subcategory_$lang']?.toString() ??
            doc['subcategory_en']?.toString() ??
            subcategory;
        final subsubDisplay = doc['subsubcategory_$lang']?.toString() ??
            doc['subsubcategory_en']?.toString() ??
            subsubcategory;

        // Add sub-subcategory level (most specific)
        if (subsubcategory.isNotEmpty &&
            subcategory.isNotEmpty &&
            category.isNotEmpty) {
          final key = '$category/$subcategory/$subsubcategory';
          if (seen.add(key)) {
            results.add(CategorySuggestion(
              categoryKey: category,
              subcategoryKey: subcategory,
              subsubcategoryKey: subsubcategory,
              displayName: '$catDisplay > $subDisplay > $subsubDisplay',
              level: 2,
              language: lang,
            ));
          }
        }

        // Add subcategory level
        if (subcategory.isNotEmpty && category.isNotEmpty) {
          final key = '$category/$subcategory';
          if (seen.add(key)) {
            results.add(CategorySuggestion(
              categoryKey: category,
              subcategoryKey: subcategory,
              displayName: '$catDisplay > $subDisplay',
              level: 1,
              language: lang,
            ));
          }
        }

        // Add main category level
        if (category.isNotEmpty) {
          if (seen.add(category)) {
            results.add(CategorySuggestion(
              categoryKey: category,
              displayName: catDisplay,
              level: 0,
              language: lang,
            ));
          }
        }

        if (results.length >= hitsPerPage) break;
      }

      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('Typesense searchCategories error: $e');
      return [];
    }
  }

  Future<List<CategorySuggestion>> searchCategoriesEnhanced({
    required String query,
    int hitsPerPage = 50,
    String? languageCode,
  }) async =>
      searchCategories(
        query: query,
        hitsPerPage: hitsPerPage,
        languageCode: languageCode,
      );

  Future<List<CategorySuggestion>> debouncedSearchCategories({
    required String query,
    int hitsPerPage = 10,
    String? languageCode,
  }) {
    _productDebounceTimer?.cancel();
    final completer = Completer<List<CategorySuggestion>>();
    _productDebounceTimer = Timer(_debounceDuration, () async {
      completer.complete(await searchCategories(
          query: query, hitsPerPage: hitsPerPage, languageCode: languageCode));
    });
    return completer.future;
  }

  // ── Firestore document fetching ───────────────────────────────────────────

  Future<List<DocumentSnapshot>> fetchDocumentSnapshotsFromTypeSenseResults(
      List<Map<String, dynamic>> results) async {
    if (results.isEmpty) return [];

    // Filter valid hits and pair with their original index to preserve order
    final validHits = <(int, String, String)>[];
    for (var i = 0; i < results.length; i++) {
      final orderId = results[i]['orderId'] as String?;
      final productId = results[i]['productId'] as String?;
      if (orderId != null && productId != null) {
        validHits.add((i, orderId, productId));
      }
    }
    if (validHits.isEmpty) return [];

    // Fire all Firestore fetches in parallel
    final futures = validHits.map((entry) async {
      final (_, orderId, productId) = entry;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .collection('items')
            .where('productId', isEqualTo: productId)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) return snap.docs.first;

        // Fallback: collectionGroup query
        final fallback = await FirebaseFirestore.instance
            .collectionGroup('items')
            .where('orderId', isEqualTo: orderId)
            .where('productId', isEqualTo: productId)
            .limit(1)
            .get();
        return fallback.docs.isNotEmpty ? fallback.docs.first : null;
      } catch (e) {
        debugPrint('fetchDocumentSnapshots error: $e');
        return null;
      }
    }).toList();

    final resolved = await Future.wait(futures);

    // Return in original Typesense order, skip nulls (failed/missing)
    return resolved.whereType<DocumentSnapshot>().toList();
  }

  // ── Facet queries ─────────────────────────────────────────────────────────

  static const String _specFacetFields =
      'brandModel,productType,consoleBrand,clothingFit,clothingTypes,clothingSizes,'
      'jewelryType,jewelryMaterials,pantSizes,pantFabricTypes,footwearSizes';

  Future<Map<String, List<Map<String, dynamic>>>> fetchSpecFacets({
    required String indexName,
    String query = '*',
    List<List<String>>? facetFilters,
    String? additionalFilterBy,
  }) async {
    final uri = _searchUri(indexName);

    final filterParts = <String>[];
    if (additionalFilterBy != null && additionalFilterBy.isNotEmpty) {
      filterParts.add(additionalFilterBy);
    }
    if (facetFilters != null) {
      for (final group in facetFilters) {
        if (group.isEmpty) continue;
        final orParts = group
            .map((f) {
              final colon = f.indexOf(':');
              if (colon < 0) return null;
              final field = f.substring(0, colon).trim();
              final value = f.substring(colon + 1).trim().replaceAll('"', '');
              return '$field:=$value';
            })
            .whereType<String>()
            .toList();

        if (orParts.length == 1) {
          filterParts.add(orParts.first);
        } else if (orParts.length > 1) {
          filterParts.add('(${orParts.join(' || ')})');
        }
      }
    }

    final params = <String, String>{
      'q': query.isEmpty ? '*' : query,
      'query_by':
          'productName,brandModel,sellerName,category_en,category_tr,category_ru,subcategory_en,subcategory_tr,subcategory_ru,subsubcategory_en,subsubcategory_tr,subsubcategory_ru',
      'per_page': '0',
      'facet_by': _specFacetFields,
      'max_facet_values': '50',
    };
    if (filterParts.isNotEmpty) {
      params['filter_by'] = filterParts.join(' && ');
    }

    try {
      final resp = await _retryOptions.retry(
        () async {
          final r = await _client
              .get(uri.replace(queryParameters: params), headers: _headers)
              .timeout(const Duration(seconds: 5));
          if (r.statusCode >= 500) {
            throw HttpException('Typesense 5xx: ${r.statusCode}', uri: uri);
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
        debugPrint('Typesense facet error ${resp.statusCode}: ${resp.body}');
        return {};
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final facetCounts = data['facet_counts'] as List? ?? [];

      final result = <String, List<Map<String, dynamic>>>{};
      for (final facet in facetCounts) {
        final fieldName = facet['field_name'] as String? ?? '';
        final counts = (facet['counts'] as List? ?? [])
            .map((c) => {
                  'value': (c as Map)['value']?.toString() ?? '',
                  'count': (c['count'] as num?)?.toInt() ?? 0,
                })
            .where((c) =>
                c['value'].toString().isNotEmpty && (c['count'] as int) > 0)
            .toList();
        if (counts.isNotEmpty) {
          result[fieldName] = counts;
        }
      }

      debugPrint('Typesense spec facets: ${result.keys}');
      return result;
    } catch (e) {
      debugPrint('Typesense fetchSpecFacets error: $e');
      return {};
    }
  }

  // ── Health check ──────────────────────────────────────────────────────────

  Future<bool> isServiceReachable() async {
    try {
      final uri = _searchUri(mainIndexName);
      final response = await _client
          .get(
            uri.replace(
                queryParameters: {'q': '*', 'query_by': 'id', 'per_page': '1'}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (e) {
      debugPrint('Typesense unreachable: $e');
      return false;
    }
  }

  // ── Multi-search disjunctive faceting ─────────────────────────────────────

  Uri get _multiSearchUri => Uri.https(_host, '/multi_search');

  /// Parse facet counts from a single facet_counts entry.
  List<Map<String, dynamic>> _parseFacetCounts(dynamic facet) {
    return ((facet as Map)['counts'] as List? ?? [])
        .map((c) => {
              'value': (c as Map)['value']?.toString() ?? '',
              'count': (c['count'] as num?)?.toInt() ?? 0,
            })
        .where(
            (c) => c['value'].toString().isNotEmpty && (c['count'] as int) > 0)
        .toList();
  }

  /// Search with proper disjunctive faceting via Typesense multi-search.
  ///
  /// Sends N+1 queries in a single HTTP request:
  ///   0. Main query — all filters applied → hits + facet counts for
  ///      non-filtered fields.
  ///   1‥N. One query per active disjunctive field — all filters EXCEPT
  ///      that field → correct facet counts showing every available option.
  ///
  /// The returned [TypeSensePage.facets] already contains the properly
  /// combined disjunctive counts — no manual merging needed.
  ///
  /// [disjunctiveFilters] — field → selected values, e.g.
  ///   `{'brandModel': ['Nike','Adidas'], 'clothingTypes': ['T-shirt']}`.
  /// [additionalFilterBy] — base context filters (category, shopId, gender)
  ///   that are always applied and do not participate in disjunctive logic.
  /// [numericFilters] — conjunctive numeric filters, e.g.
  ///   `['price>=100', 'price<=500']`.
  Future<TypeSensePage> searchWithDisjunctiveFacets({
    required String indexName,
    String query = '',
    int page = 0,
    int hitsPerPage = 20,
    String sortOption = 'date',
    String? additionalFilterBy,
    String? queryBy,
    String? includeFields,
    String facetBy = _specFacetFields,
    int maxFacetValues = 100,
    Map<String, List<String>> disjunctiveFilters = const {},
    List<String> numericFilters = const [],
  }) async {
    // ── Build filter components ────────────────────────────────────────

    // Base filters: always applied, not disjunctive
    final baseParts = <String>[];
    if (additionalFilterBy != null && additionalFilterBy.isNotEmpty) {
      baseParts.add(additionalFilterBy);
    }
    for (final nf in numericFilters) {
      final converted = nf
          .replaceAllMapped(
            RegExp(r'(\w+)\s*(>=|<=|>|<|=)\s*(\S+)'),
            (m) => '${m[1]}:${m[2]}${m[3]}',
          )
          .trim();
      if (converted.isNotEmpty) baseParts.add(converted);
    }

    // Disjunctive filter parts keyed by field name
    final disjunctiveParts = <String, String>{};
    for (final entry in disjunctiveFilters.entries) {
      if (entry.value.isEmpty) continue;
      final field = entry.key;
      final values = entry.value;
      if (values.length == 1) {
        disjunctiveParts[field] = '$field:=`${values.first}`';
      } else {
        disjunctiveParts[field] =
            '(${values.map((v) => '$field:=`$v`').join(' || ')})';
      }
    }

    // Helper: full filter_by, optionally excluding one disjunctive field
    String? _buildFilterBy({String? excludeField}) {
      final parts = [...baseParts];
      for (final entry in disjunctiveParts.entries) {
        if (entry.key != excludeField) parts.add(entry.value);
      }
      return parts.isNotEmpty ? parts.join(' && ') : null;
    }

    // ── Fast path: no active disjunctive filters → single search ──────
    final activeFields = disjunctiveParts.keys.toList();
    if (activeFields.isEmpty) {
      return searchIdsWithFacets(
        indexName: indexName,
        query: query,
        page: page,
        hitsPerPage: hitsPerPage,
        sortOption: sortOption,
        additionalFilterBy:
            baseParts.isNotEmpty ? baseParts.join(' && ') : null,
        queryBy: queryBy,
        includeFields: includeFields,
        facetBy: facetBy,
        maxFacetValues: maxFacetValues,
      );
    }

    // ── Build multi-search request ────────────────────────────────────
    final defaultQueryBy = queryBy ??
        'productName,brandModel,sellerName,'
            'category_en,category_tr,category_ru,'
            'subcategory_en,subcategory_tr,subcategory_ru,'
            'subsubcategory_en,subsubcategory_tr,subsubcategory_ru';

    final defaultIncludeFields = includeFields ??
        'id,productName,price,originalPrice,discountPercentage,brandModel,'
        'category,subcategory,subsubcategory,gender,availableColors,'
        'colorImagesJson,colorQuantitiesJson,'
        'shopId,ownerId,userId,promotionScore,createdAt,imageUrls,'
        'sellerName,condition,currency,quantity,averageRating,reviewCount,'
        'isBoosted,isFeatured,purchaseCount,bestSellerRank,deliveryOption,'
        'paused,bundleIds,videoUrl,campaignName,discountThreshold,'
        'bulkDiscountPercentage';

    // Remove actively-filtered fields from the main facet_by so we don't
    // waste cycles computing counts we'll discard anyway.
    final mainFacetFields = facetBy
        .split(',')
        .where((f) => !activeFields.contains(f.trim()))
        .join(',');

    final searches = <Map<String, dynamic>>[];

    // Search #0 — main query: all filters, returns hits + non-filtered facets
    final mainSearch = <String, dynamic>{
      'q': query.isEmpty ? '*' : query,
      'query_by': defaultQueryBy,
      'sort_by': _sortBy(sortOption),
      'per_page': hitsPerPage,
      'page': page + 1,
      'include_fields': defaultIncludeFields,
      'max_facet_values': maxFacetValues,
    };
    if (mainFacetFields.isNotEmpty) mainSearch['facet_by'] = mainFacetFields;
    final mainFilterBy = _buildFilterBy();
    if (mainFilterBy != null) mainSearch['filter_by'] = mainFilterBy;
    searches.add(mainSearch);

    // Searches #1‥N — one per active disjunctive field (facets only)
    for (final field in activeFields) {
      final facetSearch = <String, dynamic>{
        'q': query.isEmpty ? '*' : query,
        'query_by': defaultQueryBy,
        'per_page': 0,
        'facet_by': field,
        'max_facet_values': maxFacetValues,
      };
      final filterBy = _buildFilterBy(excludeField: field);
      if (filterBy != null) facetSearch['filter_by'] = filterBy;
      searches.add(facetSearch);
    }

    // ── Execute multi-search ──────────────────────────────────────────
    try {
      final resp = await _retryOptions.retry(
        () async {
          final r = await _client
              .post(
                _multiSearchUri
                    .replace(queryParameters: {'collection': indexName}),
                headers: _headers,
                body: jsonEncode({'searches': searches}),
              )
              .timeout(const Duration(seconds: 8));
          if (r.statusCode >= 500) {
            throw HttpException('Typesense multi_search 5xx: ${r.statusCode}',
                uri: _multiSearchUri);
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
        debugPrint(
            'Typesense multi_search error ${resp.statusCode}: ${resp.body}');
        return TypeSensePage(
            ids: const [], hits: const [], page: page, nbPages: page + 1);
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];
      if (results.isEmpty) {
        return TypeSensePage(
            ids: const [], hits: const [], page: page, nbPages: page + 1);
      }

      // ── Parse main result (index 0) ─────────────────────────────────
      final mainResult = results[0] as Map<String, dynamic>;
      final hits = (mainResult['hits'] as List?) ?? [];
      final found = (mainResult['found'] as int?) ?? 0;

      final ids = <String>[];
      final hitDocs = <Map<String, dynamic>>[];
      for (final h in hits) {
        final doc = Map<String, dynamic>.from((h as Map)['document'] as Map);
        doc['objectID'] = doc['id'];
        hitDocs.add(doc);

        final typesenseId = (doc['id'] ?? '').toString();
        final firestoreId = _extractFirestoreId(typesenseId, indexName);
        if (firestoreId.isNotEmpty) ids.add(firestoreId);
      }

      final perPage = hitsPerPage > 0 ? hitsPerPage : 1;
      final totalPages = (found / perPage).ceil().clamp(1, 9999);

      // ── Combine facets ──────────────────────────────────────────────
      final combinedFacets = <String, List<Map<String, dynamic>>>{};

      // Non-filtered field counts from the main query
      for (final facet in (mainResult['facet_counts'] as List? ?? [])) {
        final fieldName = (facet as Map)['field_name'] as String? ?? '';
        final counts = _parseFacetCounts(facet);
        if (counts.isNotEmpty) combinedFacets[fieldName] = counts;
      }

      // Disjunctive field counts from their dedicated sub-queries
      for (var i = 0; i < activeFields.length; i++) {
        final resultIndex = i + 1;
        if (resultIndex >= results.length) break;

        final disjResult = results[resultIndex] as Map<String, dynamic>;
        for (final facet in (disjResult['facet_counts'] as List? ?? [])) {
          final fieldName = (facet as Map)['field_name'] as String? ?? '';
          final counts = _parseFacetCounts(facet);
          if (counts.isNotEmpty) combinedFacets[fieldName] = counts;
        }
      }

      debugPrint('Typesense disjunctive: ${hits.length} hits, '
          '${combinedFacets.length} facet fields, '
          '${searches.length} sub-queries');

      return TypeSensePage(
        ids: ids,
        hits: hitDocs,
        page: page,
        nbPages: totalPages,
        totalFound: found,
        facets: combinedFacets,
      );
    } catch (e) {
      debugPrint('Typesense multi_search exception: $e');
      return TypeSensePage(
          ids: const [], hits: const [], page: page, nbPages: page + 1);
    }
  }

  void dispose() {
    _productDebounceTimer?.cancel();
    _client.close();
  }
}

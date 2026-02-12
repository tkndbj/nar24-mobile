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

class AlgoliaPage {
  final List<String> ids;
  final List<Map<String, dynamic>> hits;
  final int page;
  final int nbPages;
  AlgoliaPage({
    required this.ids,
    required this.hits,
    required this.page,
    required this.nbPages,
  });
}

class AlgoliaService {
  final String applicationId;
  final String apiKey;
  final String mainIndexName;
  final String categoryIndexName;

  AlgoliaService({
    required this.applicationId,
    required this.apiKey,
    required this.mainIndexName,
    required this.categoryIndexName,
  });

  Timer? _productDebounceTimer;
  final Duration _debounceDuration = const Duration(milliseconds: 300);

  /// Enhanced retry configuration for production reliability
  static const RetryOptions _retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(milliseconds: 500),
    randomizationFactor: 0.1,
    maxDelay: Duration(seconds: 2),
  );

  /// Progressive timeout strategy - starts with shorter timeout, increases on retry
  static const List<Duration> _timeoutProgression = [
    Duration(seconds: 3), // First attempt: 3s
    Duration(seconds: 5), // Second attempt: 5s
    Duration(seconds: 8), // Third attempt: 8s
  ];

  /// Constructs the search URL based on the given index name.
  Uri _constructSearchUri(String indexName) {
    return Uri.https(
      '$applicationId-dsn.algolia.net',
      '/1/indexes/$indexName/query',
    );
  }

  /// Returns the replica index name based on the sort option.
String _getReplicaIndexName(String indexName, String sortOption) {
  // Only use replicas for shop_products index
  // Regular products index doesn't need replicas for search
  if (!indexName.contains('shop_products')) {
    return indexName; // Return original index for non-shop searches
  }
  
  // Only apply replicas to shop_products when there's an actual sort option
  if (sortOption == 'None' || sortOption.isEmpty) {
    return indexName; // Return base index when no sorting
  }
  
  // Map sort options to replica names for shop_products only
  switch (sortOption) {
    case 'date':
      return 'shop_products_createdAt_desc';
    case 'alphabetical':
      return 'shop_products_alphabetical';
    case 'price_asc':
      return 'shop_products_price_asc';
    case 'price_desc':
      return 'shop_products_price_desc';
    default:
      return indexName; // fallback to original
  }
}

  /// Enhanced search method with comprehensive error handling and retry logic
  Future<List<T>> _searchInIndex<T>({
    required String indexName,
    required String query,
    required String sortOption,
    required T Function(Map<String, dynamic>) mapper,
    int page = 0,
    int hitsPerPage = 50,
    List<String>? filters,
  }) async {
    final String replicaIndex = _getReplicaIndexName(indexName, sortOption);
    final Uri uri = _constructSearchUri(replicaIndex);

    final Map<String, String> paramsMap = {
      'query': query,
      'page': page.toString(),
      'hitsPerPage': hitsPerPage.toString(),
      'attributesToRetrieve':
          'objectID,productName,price,imageUrls,campaignName,discountPercentage,isBoosted,dailyClickCount,averageRating,purchaseCount,createdAt,isFeatured,isTrending,colorImages,brandModel,category,subcategory,subsubcategory,condition,userId,sellerName,reviewCount,originalPrice,currency,clickCount,rankingScore,collection,isBoosted,deliveryOption,shopId,quantity',
      'attributesToHighlight': '',
    };
    if (filters != null && filters.isNotEmpty) {
      paramsMap['filters'] = filters.join(' AND ');
    }
    
    final String params = paramsMap.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final requestBody = jsonEncode({'params': params});

    int attempt = 0; // ⬅️ progresif timeout için gerçek sayaç

    return await _retryOptions.retry(
      () async {
        attempt++;
       final idx = (attempt - 1)
    .clamp(0, _timeoutProgression.length - 1)
    .toInt();
        final currentTimeout = _timeoutProgression[idx];

        try {
          final response = await http
              .post(
                uri,
                headers: {
                  'X-Algolia-Application-Id': applicationId,
                  'X-Algolia-API-Key': apiKey,
                  'Content-Type': 'application/json',
                  'User-Agent': 'YourApp/1.0 (Mobile)',
                },
                body: requestBody,
              )
              .timeout(
                currentTimeout,
                onTimeout: () => throw TimeoutException(
                  'Algolia request timeout after ${currentTimeout.inSeconds}s',
                  currentTimeout,
                ),
              );

          if (response.statusCode == 200) {
            final Map<String, dynamic> data = jsonDecode(response.body);
            final List hits = data['hits'] ?? [];
            return hits
                .map((hit) => mapper(hit as Map<String, dynamic>))
                .toList();
          } else if (response.statusCode >= 500) {
            throw HttpException(
              'Algolia server error: ${response.statusCode}',
              uri: uri,
            );
          } else {
            // 4xx -> retry etme
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
          (e.toString().contains('Failed host lookup')),
    );
  }

Future<List<Map<String, dynamic>>> searchShops({
  required String query,
  int page = 0,
  int hitsPerPage = 10,
  String? languageCode, // Add language parameter
}) async {
  try {
    final uri = Uri.https(
      '$applicationId-dsn.algolia.net',
      '/1/indexes/shops/query',
    );

    // Build attributes to retrieve including localized categories
    String categoriesField = 'categories'; // default
    if (languageCode != null && languageCode != 'en') {
      categoriesField = 'categories_$languageCode';
    }

    final Map<String, String> paramsMap = {
      'query': query,
      'page': page.toString(),
      'hitsPerPage': hitsPerPage.toString(),
      // Include both default and localized categories
      'attributesToRetrieve': 'objectID,name,profileImageUrl,categories,$categoriesField',
      'attributesToHighlight': 'name,categories,$categoriesField',
      'typoTolerance': 'true',
      'minWordSizefor1Typo': '3',
      'minWordSizefor2Typos': '6',
    };

    final String params = paramsMap.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final requestBody = jsonEncode({'params': params});

    return await _retryOptions.retry(
      () async {
        try {
          final response = await http
              .post(
                uri,
                headers: {
                  'X-Algolia-Application-Id': applicationId,
                  'X-Algolia-API-Key': apiKey,
                  'Content-Type': 'application/json',
                  'User-Agent': 'YourApp/1.0 (Mobile)',
                },
                body: requestBody,
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final Map<String, dynamic> data = jsonDecode(response.body);
            final List hits = data['hits'] ?? [];
            return hits.cast<Map<String, dynamic>>();
          } else if (response.statusCode >= 500) {
            throw HttpException(
              'Algolia server error: ${response.statusCode}',
              uri: uri,
            );
          } else {
            debugPrint('Algolia shop search error (${response.statusCode}): ${response.body}');
            return <Map<String, dynamic>>[];
          }
        } on SocketException catch (e) {
          debugPrint('Network error during shop search: $e');
          throw e;
        } on TimeoutException catch (e) {
          debugPrint('Timeout during shop search: $e');
          throw e;
        }
      },
      retryIf: (e) =>
          e is SocketException ||
          e is TimeoutException ||
          e is HttpException,
    );
  } catch (e) {
    debugPrint('Final shop search failure: $e');
    return <Map<String, dynamic>>[];
  }
}

  /// Direct Algolia search for orders index
  Future<List<Map<String, dynamic>>> searchOrdersInAlgolia({
  required String query,
  required String userId,
  required bool isSold,
  int page = 0,
  int hitsPerPage = 20,
}) async {
  final uri = Uri.https(
    '$applicationId-dsn.algolia.net',
    '/1/indexes/orders/query',
  );

  // Build filters based on whether user is searching for sold or bought items
  String userFilter;
  if (isSold) {
    userFilter = 'sellerId:"$userId"';
  } else {
    userFilter = 'buyerId:"$userId"';
  }

  final Map<String, String> paramsMap = {
    'query': query,
    'page': page.toString(),
    'hitsPerPage': hitsPerPage.toString(),
    'attributesToRetrieve': 'objectID,productName,brandModel,buyerName,sellerName,orderId,productId,price,currency,quantity,productImage,selectedColorImage,selectedColor,productAverageRating,buyerId,sellerId,shopId,timestamp',
    'attributesToHighlight': '',
    // Add these for better search matching
    'attributesToSnippet': '',
    'typoTolerance': 'true',
    'minWordSizefor1Typo': '4',
    'minWordSizefor2Typos': '8',
  };

  final String params = paramsMap.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  final requestBody = jsonEncode({'params': params});  

  try {
    final response = await http
        .post(
          uri,
          headers: {
            'X-Algolia-Application-Id': applicationId,
            'X-Algolia-API-Key': apiKey,
            'Content-Type': 'application/json',
            'User-Agent': 'YourApp/1.0 (Mobile)',
          },
          body: requestBody,
        )
        .timeout(const Duration(seconds: 10));
    

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List hits = data['hits'] ?? [];
      final int nbHits = data['nbHits'] ?? 0;
      final String processingTimeMS = data['processingTimeMS']?.toString() ?? 'unknown';
   
     
      
      return hits.cast<Map<String, dynamic>>();
    } else {
      
      return <Map<String, dynamic>>[];
    }
  } catch (e) {
    debugPrint('❌ Exception during Algolia search: $e');
    return <Map<String, dynamic>>[];
  }
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
    // Always include shop filter
    List<String> filters = ['shopId:"$shopId"'];
    
    // Add any additional filters
    if (additionalFilters != null && additionalFilters.isNotEmpty) {
      filters.addAll(additionalFilters);
    }

    return await _searchInIndex<Product>(
      indexName: 'shop_products', // Use shop_products index
      query: query,
      sortOption: sortOption,
      mapper: (hit) => Product.fromAlgolia(hit),
      page: page,
      hitsPerPage: hitsPerPage,
      filters: filters,
    );
  } catch (e) {
    print('Shop-specific Algolia search failure for shopId $shopId: $e');
    return <Product>[];
  }
}

/// Debounced search for shop products
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
      final results = await searchShopProducts(
        shopId: shopId,
        query: query,
        sortOption: sortOption,
        page: page,
        hitsPerPage: hitsPerPage,
        additionalFilters: additionalFilters,
      );
      completer.complete(results);
    } catch (e) {
      print('Debounced shop search error: $e');
      completer.complete(<Product>[]);
    }
  });

  return completer.future;
}

  /// Fetch actual DocumentSnapshot objects using Algolia search results
  Future<List<DocumentSnapshot>> fetchDocumentSnapshotsFromAlgoliaResults(
      List<Map<String, dynamic>> algoliaResults) async {
    if (algoliaResults.isEmpty) return [];

    try {
      final List<DocumentSnapshot> documents = [];
      
      for (Map<String, dynamic> hit in algoliaResults) {
        try {
          final orderId = hit['orderId'] as String?;
          final productId = hit['productId'] as String?;
          
          if (orderId == null || productId == null) {
            debugPrint('❌ Missing orderId or productId in Algolia result');
            continue;
          }
          
          
          
          // Search for the item in the specific order using productId
          final itemsQuery = await FirebaseFirestore.instance
              .collection('orders')
              .doc(orderId)
              .collection('items')
              .where('productId', isEqualTo: productId)
              .limit(1)
              .get();
          
          if (itemsQuery.docs.isNotEmpty) {
              documents.add(itemsQuery.docs.first);
              
          } else {
            
            
            // Fallback: search in collection group
            final collectionGroupQuery = await FirebaseFirestore.instance
                .collectionGroup('items')
                .where('orderId', isEqualTo: orderId)
                .where('productId', isEqualTo: productId)
                .limit(1)
                .get();
            
            if (collectionGroupQuery.docs.isNotEmpty) {
              documents.add(collectionGroupQuery.docs.first);
              
            } else {
              
            }
          }
        } catch (e) {
          
          continue;
        }
      }
      
      
      return documents;
    } catch (e) {
      
      return [];
    }
  }

  Future<List<CategorySuggestion>> searchCategories({
    required String query,
    int hitsPerPage = 10,
    String? languageCode,
  }) async {
    try {
      // Use the category index for searching
      final indexName = categoryIndexName;
      final Uri uri = _constructSearchUri(indexName);

      // Build query parameters for category search
      final Map<String, String> paramsMap = {
        'query': query,
        'hitsPerPage': hitsPerPage.toString(),
        'attributesToRetrieve':
            'objectID,categoryKey,subcategoryKey,subsubcategoryKey,displayName,type,level,languageCode',
        'attributesToHighlight': 'displayName,searchableText',
        'typoTolerance': 'true',
        'minWordSizefor1Typo': '4',
        'minWordSizefor2Typos': '8',
      };

      // Add language filter if provided
      if (languageCode != null) {
        paramsMap['filters'] = 'languageCode:$languageCode';
      }

      final String params = paramsMap.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final requestBody = jsonEncode({'params': params});

      return await _retryOptions.retry(
        () async {
          try {
            final http.Response response = await http
                .post(
                  uri,
                  headers: {
                    'X-Algolia-Application-Id': applicationId,
                    'X-Algolia-API-Key': apiKey,
                    'Content-Type': 'application/json',
                    'User-Agent': 'YourApp/1.0 (Mobile)',
                  },
                  body: requestBody,
                )
                .timeout(const Duration(seconds: 5));

            if (response.statusCode == 200) {
              final Map<String, dynamic> data = jsonDecode(response.body);
              final List hits = data['hits'] ?? [];

              return hits
                  .map((hit) => CategorySuggestion.fromAlgolia(
                      hit as Map<String, dynamic>))
                  .toList();
            } else if (response.statusCode >= 500) {
              throw HttpException(
                'Algolia server error: ${response.statusCode}',
                uri: uri,
              );
            } else {
              print(
                  'Algolia category search error (${response.statusCode}): ${response.body}');
              return <CategorySuggestion>[];
            }
          } on SocketException catch (e) {
            print('Network error during category search: $e');
            throw e;
          } on TimeoutException catch (e) {
            print('Timeout during category search: $e');
            throw e;
          } on FormatException catch (e) {
            print('JSON parsing error from category search: $e');
            return <CategorySuggestion>[];
          }
        },
        retryIf: (e) {
          return e is SocketException ||
              e is TimeoutException ||
              e is HttpException ||
              (e.toString().contains('Failed host lookup'));
        },
        onRetry: (e) {
          print('Retrying category search after error: $e');
        },
      );
    } catch (e) {
      print('Final category search failure: $e');
      return <CategorySuggestion>[];
    }
  }

  Future<List<CategorySuggestion>> searchCategoriesEnhanced({
  required String query,
  int hitsPerPage = 50, // Increased default for better scoring
  String? languageCode,
}) async {
  try {
    final indexName = categoryIndexName;
    final Uri uri = _constructSearchUri(indexName);

    // Enhanced query parameters for better matching
    final Map<String, String> paramsMap = {
      'query': query,
      'hitsPerPage': hitsPerPage.toString(),
      'attributesToRetrieve': 'objectID,categoryKey,subcategoryKey,subsubcategoryKey,displayName,type,level,language,keywords,path,pathKeys',
      // Improved highlighting for relevance
      'attributesToHighlight': 'displayName,categoryKey,subcategoryKey,subsubcategoryKey,keywords',
      // Enhanced typo tolerance
      'typoTolerance': 'true',
      'minWordSizefor1Typo': '3', // More lenient for shorter words
      'minWordSizefor2Typos': '7',
      // Better ranking
      'ranking': 'typo,geo,words,filters,proximity,attribute,exact,custom',
      // Remove common words that don't add value
      'removeWordsIfNoResults': 'allOptional',
      // Better faceting
      'maxFacetHits': '20',
    };

    // Add language filter if provided
    if (languageCode != null) {
      paramsMap['filters'] = 'language:$languageCode';
    }

    // Multi-language fallback if no results in primary language
    if (languageCode != null && languageCode != 'en') {
      // First try with specific language, then fallback to English
      final results = await _performCategorySearch(uri, paramsMap);
      if (results.isEmpty && languageCode != 'en') {
        // Fallback to English
        paramsMap['filters'] = 'language:en';
        return await _performCategorySearch(uri, paramsMap);
      }
      return results;
    } else {
      return await _performCategorySearch(uri, paramsMap);
    }
  } catch (e) {
    debugPrint('Enhanced category search failure: $e');
    return <CategorySuggestion>[];
  }
}

Future<List<CategorySuggestion>> _performCategorySearch(
  Uri uri, 
  Map<String, String> paramsMap
) async {
  final String params = paramsMap.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  final requestBody = jsonEncode({'params': params});

  return await _retryOptions.retry(
    () async {
      try {
        final http.Response response = await http
            .post(
              uri,
              headers: {
                'X-Algolia-Application-Id': applicationId,
                'X-Algolia-API-Key': apiKey,
                'Content-Type': 'application/json',
                'User-Agent': 'YourApp/1.0 (Mobile)',
              },
              body: requestBody,
            )
            .timeout(const Duration(seconds: 6)); // Slightly longer timeout

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          final List hits = data['hits'] ?? [];
          final int processingTimeMS = data['processingTimeMS'] ?? 0;
          
          debugPrint('Category search: ${hits.length} results in ${processingTimeMS}ms');

          return hits.map((hit) {
            final hitMap = hit as Map<String, dynamic>;
            
            // Extract highlighted matches for scoring
            final highlighted = hitMap['_highlightResult'] as Map<String, dynamic>?;
            final matchedKeywords = <String>[];
            
            if (highlighted != null) {
              // Extract matched keywords from highlighting
              highlighted.forEach((key, value) {
                if (value is Map && value['matchLevel'] == 'full') {
                  matchedKeywords.add(key);
                }
              });
            }
            
            // Create CategorySuggestion with enhanced data
            final suggestion = CategorySuggestion.fromAlgolia(hitMap);
            
            // Add matched keywords for scoring
            return CategorySuggestion(
              categoryKey: suggestion.categoryKey,
              subcategoryKey: suggestion.subcategoryKey,
              subsubcategoryKey: suggestion.subsubcategoryKey,
              displayName: suggestion.displayName,
              level: suggestion.level,
              language: suggestion.language,
              matchedKeywords: matchedKeywords.isEmpty ? null : matchedKeywords,
            );
          }).toList();
        } else if (response.statusCode >= 500) {
          throw HttpException(
            'Algolia server error: ${response.statusCode}',
            uri: uri,
          );
        } else {
          debugPrint('Algolia category search error (${response.statusCode}): ${response.body}');
          return <CategorySuggestion>[];
        }
      } on SocketException catch (e) {
        debugPrint('Network error during enhanced category search: $e');
        throw e;
      } on TimeoutException catch (e) {
        debugPrint('Timeout during enhanced category search: $e');
        throw e;
      } on FormatException catch (e) {
        debugPrint('JSON parsing error from enhanced category search: $e');
        return <CategorySuggestion>[];
      }
    },
    retryIf: (e) {
      return e is SocketException ||
          e is TimeoutException ||
          e is HttpException ||
          (e.toString().contains('Failed host lookup'));
    },
    onRetry: (e) {
      debugPrint('Retrying enhanced category search after error: $e');
    },
  );
}

  /// Debounced category search
  Future<List<CategorySuggestion>> debouncedSearchCategories({
    required String query,
    int hitsPerPage = 10,
    String? languageCode,
  }) {
    _productDebounceTimer?.cancel();
    final completer = Completer<List<CategorySuggestion>>();

    _productDebounceTimer = Timer(_debounceDuration, () async {
      try {
        final results = await searchCategories(
          query: query,
          hitsPerPage: hitsPerPage,
          languageCode: languageCode,
        );
        completer.complete(results);
      } catch (e) {
        print('Debounced category search error: $e');
        completer.complete(<CategorySuggestion>[]);
      }
    });

    return completer.future;
  }

  /// Searches for Products with enhanced error handling
Future<List<ProductSummary>> searchProducts({
  required String query,
  required String sortOption,
  int page = 0,
  int hitsPerPage = 50,
  List<String>? filters,
}) async {
  try {
    return await _searchInIndex<ProductSummary>(
      indexName: mainIndexName,
      query: query,
      sortOption: sortOption,
      mapper: (hit) => ProductSummary.fromAlgolia(hit),
      page: page,
      hitsPerPage: hitsPerPage,
      filters: filters,
    );
  } catch (e) {
    print('Final Algolia search failure for index $mainIndexName: $e');
    return <ProductSummary>[];
  }
}

  /// Debounced search for Products with enhanced error handling
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
      final results = await searchProducts(
        query: query,
        sortOption: sortOption,
        page: page,
        hitsPerPage: hitsPerPage,
        filters: filters,
      );
      completer.complete(results);
    } catch (e) {
      print('Debounced search error: $e');
      completer.complete(<ProductSummary>[]);
    }
  });

  return completer.future;
}

 Future<AlgoliaPage> searchIdsWithFacets({
  required String indexName,
  String query = '',
  int page = 0,
  int hitsPerPage = 20,
  List<List<String>>? facetFilters,
  List<String>? numericFilters,
}) async {
  final uri = _constructSearchUri(indexName);

  String _enc(dynamic v) =>
      Uri.encodeQueryComponent(v is List ? jsonEncode(v) : v.toString());

  final params = StringBuffer()
    ..write('query=${_enc(query)}')
    ..write('&page=${_enc(page)}')
    ..write('&hitsPerPage=${_enc(hitsPerPage)}')
    // Request only what we need - ilanNo contains the Firestore doc ID
    ..write('&attributesToRetrieve=${_enc([
  'objectID', 'ilanNo', 'productName', 'price', 'originalPrice',
  'discountPercentage', 'currency', 'condition', 'brandModel',
  'imageUrls', 'averageRating', 'reviewCount', 'category',
  'subcategory', 'subsubcategory', 'gender', 'availableColors',
  'colorImages', 'sellerName', 'shopId', 'userId', 'ownerId',
  'quantity', 'colorQuantities', 'isBoosted', 'isFeatured',
  'isTrending', 'purchaseCount', 'bestSellerRank', 'deliveryOption',
  'paused', 'campaignName', 'bundleIds', 'discountThreshold',
  'bulkDiscountPercentage', 'videoUrl', 'createdAt',
  'rankingScore', 'promotionScore'
])}')
    ..write('&attributesToHighlight=${_enc('')}');

  if (facetFilters != null && facetFilters.isNotEmpty) {
    params.write('&facetFilters=${_enc(facetFilters)}');
  }
  if (numericFilters != null && numericFilters.isNotEmpty) {
    params.write('&numericFilters=${_enc(numericFilters)}');
  }

  final requestBody = jsonEncode({'params': params.toString()});
  debugPrint('Algolia request for $indexName: facetFilters=$facetFilters, numericFilters=$numericFilters');

  try {
    final resp = await _retryOptions.retry(() async {
      final r = await http
          .post(
            uri,
            headers: {
              'X-Algolia-Application-Id': applicationId,
              'X-Algolia-API-Key': apiKey,
              'Content-Type': 'application/json',
              'User-Agent': 'YourApp/1.0 (Mobile)',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 5));
      if (r.statusCode >= 500) {
        throw HttpException('Algolia 5xx: ${r.statusCode}', uri: uri);
      }
      return r;
    }, retryIf: (e) =>
        e is SocketException ||
        e is TimeoutException ||
        e is HttpException ||
        (e.toString().contains('Failed host lookup')));

    if (resp.statusCode != 200) {
      debugPrint('Algolia error ${resp.statusCode}: ${resp.body}');
      return AlgoliaPage(ids: const [], hits: const [], page: page, nbPages: page + 1);
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final hits = (data['hits'] as List?) ?? const [];
    final ids = <String>[];

    debugPrint('Algolia returned ${hits.length} hits');

    for (final h in hits) {
      final m = Map<String, dynamic>.from(h as Map);
      
      // The ilanNo field contains the actual Firestore document ID
      final id = m['ilanNo']?.toString();
      
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      } else {
        // Fallback: try to extract from objectID
        final objectId = (m['objectID'] ?? '').toString();
        if (objectId.startsWith('shop_products_')) {
          final extractedId = objectId.substring('shop_products_'.length);
          if (extractedId.isNotEmpty) {
            ids.add(extractedId);
            debugPrint('Warning: Had to extract ID from objectID for record missing ilanNo');
          }
        }
      }
    }

    final curPage = (data['page'] as int?) ?? page;
    final nbPages = (data['nbPages'] as int?) ?? 1;

    debugPrint('Extracted ${ids.length} Firestore IDs from Algolia results');
    if (ids.isNotEmpty) {
      debugPrint('Sample IDs: ${ids.take(3).join(", ")}');
    }
    
    return AlgoliaPage(
  ids: ids,
  hits: hits.cast<Map<String, dynamic>>(),
  page: curPage,
  nbPages: nbPages,
);
  } catch (e) {
    debugPrint('Algolia exception: $e');
    return AlgoliaPage(ids: const [], hits: const [], page: page, nbPages: page + 1);
  }
}

  /// Check if Algolia service is reachable (useful for health checks)
  Future<bool> isServiceReachable() async {
    try {
      final uri = _constructSearchUri(mainIndexName);
      final response = await http
          .post(
            uri,
            headers: {
              'X-Algolia-Application-Id': applicationId,
              'X-Algolia-API-Key': apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'params': 'query=&hitsPerPage=1'}),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode < 500;
    } catch (e) {
      print('Algolia service unreachable: $e');
      return false;
    }
  }
}
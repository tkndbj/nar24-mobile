// import 'dart:async';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:rxdart/rxdart.dart';
// import '../models/product.dart';
// import '../user_provider.dart';

// class SpecialFilterProviderTeras with ChangeNotifier {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final UserProvider userProvider;

//   SpecialFilterProviderTeras(this.userProvider) {
//     _productsStream = _productIdsSubject.switchMap((productIds) {
//       if (productIds.isEmpty) {
//         return Stream.value(<Product>[]);
//       }
//       final productSnapshots = productIds.map((id) {
//         return _firestore
//             .collection('products')
//             .doc(id)
//             .snapshots()
//             .map((snap) {
//           if (!snap.exists) return null;
//           return Product.fromDocument(snap);
//         });
//       }).toList();
//       return Rx.combineLatestList(productSnapshots).map((list) {
//         return list.whereType<Product>().toList();
//       });
//     }).debounceTime(const Duration(milliseconds: 100));
//   }

//   String? _specialFilter;
//   String? get specialFilter => _specialFilter;

//   // Store products for each filter type
//   final Map<String, List<Product>> _filterProducts = {
//     'Deals': [],
//     'Featured': [],
//     'Trending': [],
//     '5-Star': [],
//     'Best Sellers': [],
//   };
//   List<Product> getProducts(String filterType) =>
//       _filterProducts[filterType] ?? [];

//   // Store product IDs for each filter type
//   final Map<String, Set<String>> _filterProductIds = {
//     'Deals': {},
//     'Featured': {},
//     'Trending': {},
//     '5-Star': {},
//     'Best Sellers': {},
//   };

//   final BehaviorSubject<List<String>> _productIdsSubject =
//       BehaviorSubject<List<String>>.seeded([]);
//   late final Stream<List<Product>> _productsStream;
//   Stream<List<Product>> get productsStream => _productsStream;

//   // Pagination and loading states per filter
//   final Map<String, int> _currentPages = {
//     'Deals': 0,
//     'Featured': 0,
//     'Trending': 0,
//     '5-Star': 0,
//     'Best Sellers': 0,
//   };
//   final Map<String, bool> _hasMore = {
//     'Deals': true,
//     'Featured': true,
//     'Trending': true,
//     '5-Star': true,
//     'Best Sellers': true,
//   };
//   final Map<String, bool> _isLoadingMore = {
//     'Deals': false,
//     'Featured': false,
//     'Trending': false,
//     '5-Star': false,
//     'Best Sellers': false,
//   };
//   final Map<String, DocumentSnapshot?> _lastDocuments = {
//     'Deals': null,
//     'Featured': null,
//     'Trending': null,
//     '5-Star': null,
//     'Best Sellers': null,
//   };

//   bool hasMore(String filterType) => _hasMore[filterType] ?? true;
//   bool isLoadingMore(String filterType) => _isLoadingMore[filterType] ?? false;

//   final Map<String, List<Product>> _productCache = {};
//   final Map<String, DateTime> _cacheTimestamps = {};
//   static const Duration _cacheTTL = Duration(minutes: 5);

//   final Map<String, bool> _isFiltering = {
//     'Deals': false,
//     'Featured': false,
//     'Trending': false,
//     '5-Star': false,
//     'Best Sellers': false,
//   };
//   bool isFiltering(String filterType) => _isFiltering[filterType] ?? false;

//   Future<void> fetchProducts({
//     required String filterType,
//     int page = 0,
//     int limit = 20,
//   }) async {
//     if (filterType.isEmpty) {
//       _filterProducts[filterType]?.clear();
//       _filterProductIds[filterType]?.clear();
//       _hasMore[filterType] = false;
//       _isFiltering[filterType] = false;
//       notifyListeners();
//       return;
//     }

//     if (_isFiltering[filterType]!) return; // Prevent concurrent fetches
//     _isFiltering[filterType] = true;
//     notifyListeners();

//     final cacheKey = '$filterType|$page';
//     final now = DateTime.now();
//     final cachedTime = _cacheTimestamps[cacheKey];
//     final isCacheValid =
//         cachedTime != null && now.difference(cachedTime) < _cacheTTL;

//     if (isCacheValid && _productCache.containsKey(cacheKey)) {
//       final cachedProducts = _productCache[cacheKey]!;
//       if (page == 0) {
//         _filterProducts[filterType]?.clear();
//         _filterProductIds[filterType]?.clear();
//       }
//       for (var product in cachedProducts) {
//         if (_filterProductIds[filterType]!.add(product.id)) {
//           _filterProducts[filterType]!.add(product);
//         }
//       }
//       _hasMore[filterType] = cachedProducts.length >= limit;
//       if (filterType == _specialFilter) {
//         _productIdsSubject
//             .add(_filterProducts[filterType]!.map((p) => p.id).toList());
//       }
//       _isFiltering[filterType] = false;
//       notifyListeners();
//       return;
//     }

//     try {
//       Query query = _firestore.collection('products');

//       switch (filterType) {
//         case 'Deals':
//           query = query
//               .where('discountPercentage', isGreaterThan: 0)
//               .orderBy('discountPercentage', descending: true)
//               .orderBy('createdAt', descending: true);
//           break;
//         case 'Featured':
//           query = query
//               .where('isBoosted', isEqualTo: true)
//               .orderBy('createdAt', descending: true);
//           break;
//         case 'Trending':
//           query = query
//               .where('dailyClickCount', isGreaterThanOrEqualTo: 10)
//               .orderBy('dailyClickCount', descending: true)
//               .orderBy('createdAt', descending: true);
//           break;
//         case '5-Star':
//           query = query
//               .where('averageRating', isEqualTo: 5)
//               .orderBy('createdAt', descending: true);
//           break;
//         case 'Best Sellers':
//           query = query
//               .where('purchaseCount', isGreaterThan: 0)
//               .orderBy('purchaseCount', descending: true)
//               .orderBy('createdAt', descending: true);
//           break;
//       }

//       if (page > 0 && _lastDocuments[filterType] != null) {
//         query = query.startAfterDocument(_lastDocuments[filterType]!);
//       }
//       query = query.limit(limit);

//       final snapshot = await query.get();
//       final newProducts =
//           snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

//       if (snapshot.docs.isNotEmpty) {
//         _lastDocuments[filterType] = snapshot.docs.last;
//       }

//       if (page == 0) {
//         _filterProducts[filterType]?.clear();
//         _filterProductIds[filterType]?.clear();
//       }
//       for (var product in newProducts) {
//         if (_filterProductIds[filterType]!.add(product.id)) {
//           _filterProducts[filterType]!.add(product);
//         }
//       }

//       _productCache[cacheKey] = List.from(newProducts);
//       _cacheTimestamps[cacheKey] = now;

//       if (filterType == _specialFilter) {
//         _productIdsSubject
//             .add(_filterProducts[filterType]!.map((p) => p.id).toList());
//       }
//       _hasMore[filterType] = newProducts.length >= limit;
//     } catch (e) {
//       debugPrint('Error fetching products for $filterType: $e');
//       _hasMore[filterType] = false;
//     } finally {
//       _isFiltering[filterType] = false;
//       notifyListeners();
//     }
//   }

//   void setSpecialFilter(String filter) {
//     if (_specialFilter != filter) {
//       _specialFilter = filter;
//       if (filter.isEmpty) {
//         _productIdsSubject.add([]);
//         notifyListeners();
//         return;
//       }
//       _currentPages[filter] = 0;
//       _hasMore[filter] = true;
//       _lastDocuments[filter] = null;

//       // Immediately update with cached data if available
//       if (_filterProducts[filter]?.isNotEmpty ?? false) {
//         _productIdsSubject
//             .add(_filterProducts[filter]!.map((p) => p.id).toList());
//         _isFiltering[filter] = false;
//       } else {
//         _productIdsSubject.add([]);
//         _isFiltering[filter] = true;
//         WidgetsBinding.instance.addPostFrameCallback((_) {
//           fetchProducts(filterType: filter, page: 0);
//         });
//       }
//       notifyListeners();
//     }
//   }

//   Future<void> prefetchAllFilters() async {
//     final filters = ['Deals', 'Featured', 'Trending', '5-Star', 'Best Sellers'];
//     for (var filter in filters) {
//       try {
//         await fetchProducts(filterType: filter, page: 0, limit: 20);
//       } catch (e) {
//         debugPrint('Error prefetching $filter: $e');
//       }
//     }
//   }

//   Future<void> fetchMoreProducts(String filterType) async {
//     if (!_hasMore[filterType]! || _isLoadingMore[filterType]!) return;
//     _isLoadingMore[filterType] = true;
//     notifyListeners();
//     _currentPages[filterType] = (_currentPages[filterType] ?? 0) + 1;
//     await fetchProducts(
//         filterType: filterType, page: _currentPages[filterType]!);
//     _isLoadingMore[filterType] = false;
//     notifyListeners();
//   }

//   Future<void> refreshProducts(String filterType) async {
//     _currentPages[filterType] = 0;
//     _hasMore[filterType] = true;
//     _lastDocuments[filterType] = null;
//     await fetchProducts(filterType: filterType, page: 0);
//   }

//   @override
//   void dispose() {
//     _productIdsSubject.close();
//     super.dispose();
//   }
// }

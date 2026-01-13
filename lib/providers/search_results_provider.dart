// lib/providers/search_results_provider.dart
import 'package:flutter/foundation.dart';
import '../models/product.dart';

class SearchResultsProvider with ChangeNotifier {
  // Raw search results from API
  List<Product> _rawProducts = [];

  // Filtered and processed products for UI
  List<Product> _filteredProducts = [];
  List<Product> get filteredProducts => List.unmodifiable(_filteredProducts);

  // Current filter state
  String? _currentFilter;
  String? get currentFilter => _currentFilter;

  // Sort option
  String _sortOption = 'None';
  String get sortOption => _sortOption;

  /// Set the raw products from search API
  void setRawProducts(List<Product> products) {
    _rawProducts = List.from(products);
    _applyFiltersAndSort();
  }

  /// Add more products (for pagination)
  void addMoreProducts(List<Product> products) {
    _rawProducts.addAll(products);
    _applyFiltersAndSort();
  }

  /// Clear all products
  void clearProducts() {
    _rawProducts.clear();
    _filteredProducts.clear();
    notifyListeners();
  }

  /// Apply a quick filter
  void setFilter(String? filter) {
    if (_currentFilter == filter) return;
    _currentFilter = filter;
    _applyFiltersAndSort();
  }

  /// Set sort option
  void setSortOption(String sortOption) {
    if (_sortOption == sortOption) return;
    _sortOption = sortOption;
    _applyFiltersAndSort();
  }

  /// Apply current filter and sort to raw products
  void _applyFiltersAndSort() {
    // Start with raw products
    List<Product> result = List.from(_rawProducts);

    // Apply filter logic
    result = _applyFilterLogic(result, _currentFilter);

    // Apply sorting
    _applySorting(result);

    // Prioritize boosted products
    _prioritizeBoosted(result);

    // Update filtered products
    _filteredProducts = result;
    notifyListeners();
  }

  /// Apply filter logic based on filter type
  List<Product> _applyFilterLogic(List<Product> products, String? filter) {
    switch (filter) {
      case 'deals':
        return products.where((p) => (p.discountPercentage ?? 0) > 0).toList();
      case 'boosted':
        return products.where((p) => p.isBoosted).toList();
      case 'trending':
        return products.where((p) => p.dailyClickCount >= 10).toList();
      case 'fiveStar':
        return products.where((p) => p.averageRating == 5).toList();
      case 'bestSellers':
        final sorted = List<Product>.from(products);
        sorted.sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));
        return sorted;
      default:
        return products; // 'All' filter or empty filter
    }
  }

  /// Apply sorting to the list
  void _applySorting(List<Product> products) {
    switch (_sortOption) {
      case 'Alphabetical':
        products.sort((a, b) =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
        break;
      case 'Date':
        products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'Price Low to High':
        products.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'Price High to Low':
        products.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'None':
      default:
        break;
    }
  }

  /// Prioritize boosted products
  void _prioritizeBoosted(List<Product> products) {
    products.sort((a, b) {
      if (a.isBoosted && !b.isBoosted) return -1;
      if (!a.isBoosted && b.isBoosted) return 1;
      return 0;
    });
  }

  /// Get boosted products from filtered list
  List<Product> get boostedProducts {
    return _filteredProducts.where((p) => p.isBoosted).toList();
  }

  /// Check if filtered list is empty
  bool get isEmpty => _filteredProducts.isEmpty;

  /// Check if raw products are empty
  bool get hasNoData => _rawProducts.isEmpty;
}

import 'package:flutter/foundation.dart';
import '../models/product_summary.dart';

class SearchResultsProvider with ChangeNotifier {
  List<ProductSummary> _rawProducts = [];

  List<ProductSummary> _filteredProducts = [];
  List<ProductSummary> get filteredProducts => List.unmodifiable(_filteredProducts);

  String? _currentFilter;
  String? get currentFilter => _currentFilter;

  String _sortOption = 'None';
  String get sortOption => _sortOption;

  void setRawProducts(List<ProductSummary> products) {
    _rawProducts = List.from(products);
    _applyFiltersAndSort();
  }

  void addMoreProducts(List<ProductSummary> products) {
    _rawProducts.addAll(products);
    _applyFiltersAndSort();
  }

  void clearProducts() {
    _rawProducts.clear();
    _filteredProducts.clear();
    notifyListeners();
  }

  void setFilter(String? filter) {
    if (_currentFilter == filter) return;
    _currentFilter = filter;
    _applyFiltersAndSort();
  }

  void setSortOption(String sortOption) {
    if (_sortOption == sortOption) return;
    _sortOption = sortOption;
    _applyFiltersAndSort();
  }

  void _applyFiltersAndSort() {
    List<ProductSummary> result = List.from(_rawProducts);
 
    _applySorting(result);
    _prioritizeBoosted(result);
    _filteredProducts = result;
    notifyListeners();
  }



  void _applySorting(List<ProductSummary> products) {
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

  void _prioritizeBoosted(List<ProductSummary> products) {
    products.sort((a, b) {
      if (a.isBoosted && !b.isBoosted) return -1;
      if (!a.isBoosted && b.isBoosted) return 1;
      return 0;
    });
  }

  List<ProductSummary> get boostedProducts {
    return _filteredProducts.where((p) => p.isBoosted).toList();
  }

  bool get isEmpty => _filteredProducts.isEmpty;
  bool get hasNoData => _rawProducts.isEmpty;
}
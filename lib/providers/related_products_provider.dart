import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/related_products_service.dart';

class RelatedProductsProvider with ChangeNotifier {
  List<Product> _relatedProducts = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProductId;

  List<Product> get relatedProducts => _relatedProducts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load related products for a given product
  Future<void> loadRelatedProducts(Product product) async {
    // Don't reload if it's the same product and we already have results
    if (_currentProductId == product.id && _relatedProducts.isNotEmpty) {
      return;
    }

    _currentProductId = product.id;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _relatedProducts =
          await RelatedProductsService.getRelatedProducts(product);
      _error = null;
    } catch (e) {
      _error = e.toString();
      _relatedProducts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear current related products
  void clearRelatedProducts() {
    _relatedProducts = [];
    _currentProductId = null;
    _error = null;
    notifyListeners();
  }
}

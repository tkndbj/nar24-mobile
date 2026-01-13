// lib/helpers/firestore_helper.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'dart:async';
import 'package:async/async.dart'; // Ensure you have added the 'async' package in pubspec.yaml

class FirestoreHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetches products from Firestore based on a list of product IDs.
  /// Handles batching if the list exceeds 10 IDs.
  Future<List<Product>> fetchProductsByIds(List<String> productIds) async {
    if (productIds.isEmpty) return [];

    const int batchSize = 10;
    List<Product> products = [];

    for (int i = 0; i < productIds.length; i += batchSize) {
      int end =
          (i + batchSize < productIds.length) ? i + batchSize : productIds.length;
      List<String> batchIds = productIds.sublist(i, end);

      QuerySnapshot querySnapshot = await _firestore
          .collection('products')
          .where(FieldPath.documentId, whereIn: batchIds)
          .get();

      products.addAll(
          querySnapshot.docs.map((doc) => Product.fromDocument(doc)).toList());
    }

    return products;
  }

  /// Streams products from Firestore based on a list of product IDs.
  /// Handles batching if the list exceeds 10 IDs.
  Stream<List<Product>> streamProductsByIds(List<String> productIds) {
    if (productIds.isEmpty) {
      return Stream.value([]);
    }

    const int batchSize = 10;
    List<String> allProductIds = List.from(productIds);

    // Create a StreamGroup to merge multiple streams
    final StreamGroup<List<Product>> streamGroup = StreamGroup<List<Product>>();

    // Map to hold the latest data for each product
    final Map<String, Product> productMap = {};

    for (int i = 0; i < allProductIds.length; i += batchSize) {
      int end = (i + batchSize < allProductIds.length)
          ? i + batchSize
          : allProductIds.length;
      List<String> batchIds = allProductIds.sublist(i, end);

      Stream<List<Product>> batchStream = _firestore
          .collection('products')
          .where(FieldPath.documentId, whereIn: batchIds)
          .snapshots()
          .map((snapshot) =>
              snapshot.docs.map((doc) => Product.fromDocument(doc)).toList());

      streamGroup.add(batchStream);
    }

    streamGroup.close();

    // Use a broadcast stream to allow multiple listeners if needed
    return streamGroup.stream.transform(
      StreamTransformer<List<Product>, List<Product>>.fromHandlers(
        handleData: (batchProducts, sink) {
          // Update the productMap with the latest data
          for (var product in batchProducts) {
            productMap[product.id] = product;
          }
          // Emit the combined list
          sink.add(productMap.values.toList());
        },
        handleError: (error, stack, sink) {
          sink.addError(error, stack);
        },
        handleDone: (sink) {
          sink.close();
        },
      ),
    ).asBroadcastStream();
  }

  /// Fetches related products based on categoryId and subcategoryId, excluding products already in the cart.
   Future<List<Product>> fetchRelatedProducts(
    Set<String> excludeProductIds,
    String? category,
    String? subcategory,
  ) async {
    Query query = _firestore.collection('products');

    // Apply filters based on subcategory or category
    if (subcategory != null && subcategory.isNotEmpty) {
      query = query.where('subcategory', isEqualTo: subcategory);
    } else if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    // Fetch products
    QuerySnapshot querySnapshot = await query.limit(20).get(); // Fetch more to filter out excluded IDs

    List<Product> products = querySnapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

    // Exclude products already in the cart
    products.removeWhere((product) => excludeProductIds.contains(product.id));

    // Return limited number of products
    return products.take(10).toList();
  }
}

// // lib/providers/stat_provider.dart

// import 'dart:async';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import '../models/product.dart';
// import '../models/transaction.dart'; // Import TransactionModel
// import 'package:collection/collection.dart'; // Ensure this import is included
// import 'package:firebase_auth/firebase_auth.dart';

// class StatProvider with ChangeNotifier {
//   String userId = '';
//   late StreamSubscription<User?> _authSubscription;

//   List<Product> _userProducts = []; // All products of the user
//   List<Product> get userProducts => _userProducts;

//   List<TransactionModel> _transactions = [];
//   List<TransactionModel> get transactions => _transactions;

//   double _totalEarnings = 0.0;
//   double get totalEarnings => _totalEarnings;

//   Map<DateTime, double> _earningsOverTime = {};
//   Map<DateTime, double> get earningsOverTime => _earningsOverTime;

//   Product? _mostSoldProduct;
//   Product? get mostSoldProduct => _mostSoldProduct;

//   Product? _mostClickedProduct;
//   Product? get mostClickedProduct => _mostClickedProduct;

//   Product? _mostFavoritedProduct;
//   Product? get mostFavoritedProduct => _mostFavoritedProduct;

//   Product? _mostAddedToCartProduct;
//   Product? get mostAddedToCartProduct => _mostAddedToCartProduct;

//   Product? _highestRatedProduct;
//   Product? get highestRatedProduct => _highestRatedProduct;

//   int _mostSoldProductSoldQuantity = 0;
//   int get mostSoldProductSoldQuantity => _mostSoldProductSoldQuantity;

//   DateTime _startDate = DateTime.now().subtract(Duration(days: 30));
//   DateTime get startDate => _startDate;
//   DateTime _endDate = DateTime.now();
//   DateTime get endDate => _endDate;

//   StatProvider() {
//     // Listen to authentication state changes
//     _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
//       if (user != null) {
//         userId = user.uid;
//         print('StatProvider: User logged in with userId: $userId');
//         _initializeData();
//       } else {
//         userId = '';
//         print('StatProvider: User logged out.');
//         // Clear existing data
//         _userProducts = [];
//         _transactions = [];
//         _totalEarnings = 0.0;
//         _earningsOverTime = {};
//         _mostSoldProduct = null;
//         _mostClickedProduct = null;
//         _mostFavoritedProduct = null;
//         _mostAddedToCartProduct = null;
//         _highestRatedProduct = null;
//         _mostSoldProductSoldQuantity = 0;
//         notifyListeners();
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _authSubscription.cancel();
//     super.dispose();
//   }

//   // Initialize data
//   Future<void> _initializeData() async {
//     await _fetchUserProducts(); // Fetch all products of the user
//     await _fetchTransactions(); // Fetch all transactions
//     _calculateTotalEarnings(); // Calculate total earnings
//     await _calculateEarningsOverTime(); // Calculate earnings over time
//     _findMostSoldProduct(); // Find most sold product
//     _computeProductStatistics(); // Compute product-related statistics
//     notifyListeners();
//   }

//   // Function to update the date range
//   Future<void> updateDateRange(DateTime start, DateTime end) async {
//     _startDate = start;
//     _endDate = end;
//     if (userId.isNotEmpty) {
//       await _calculateEarningsOverTime(); // Recalculate data with new date range
//       notifyListeners();
//     }
//   }

//   Future<void> _fetchUserProducts() async {
//     if (userId.isEmpty) {
//       print('StatProvider: Cannot fetch products - userId is empty.');
//       return;
//     }

//     try {
//       // Fetch all products where userId equals the seller's ID
//       QuerySnapshot productsSnapshot = await FirebaseFirestore.instance
//           .collection('products')
//           .where('userId', isEqualTo: userId)
//           .get();

//       _userProducts = productsSnapshot.docs
//           .map((doc) => Product.fromDocument(doc))
//           .toList();

//       print('StatProvider: Fetched ${_userProducts.length} products.');
//     } catch (e) {
//       print('StatProvider: Error fetching products: $e');
//     }
//   }

//   Future<void> _fetchTransactions() async {
//     if (userId.isEmpty) {
//       print('StatProvider: Cannot fetch transactions - userId is empty.');
//       return;
//     }

//     try {
//       // Fetch all transactions where role equals 'seller' or 'buyer'
//       QuerySnapshot transactionsSnapshot = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(userId)
//           .collection('transactions')
//           .where('role', whereIn: ['seller', 'buyer']).get();

//       _transactions = transactionsSnapshot.docs
//           .map((doc) => TransactionModel.fromDocument(doc))
//           .toList();

//       print('StatProvider: Fetched ${_transactions.length} transactions.');
//     } catch (e) {
//       print('StatProvider: Error fetching transactions: $e');
//     }
//   }

//   void _calculateTotalEarnings() {
//     // Sum up the 'price * quantity' from all transactions where role is 'seller' and quantity > 0
//     _totalEarnings = _transactions
//         .where((tx) => tx.role == 'seller' && tx.quantity > 0)
//         .fold(0.0, (sum, tx) => sum + (tx.price * tx.quantity));

//     print('StatProvider: Total Earnings: $_totalEarnings');
//   }

//   Future<void> _calculateEarningsOverTime() async {
//     _earningsOverTime.clear();

//     // Filter transactions within the date range and with role 'seller' and quantity > 0
//     List<TransactionModel> transactionsInRange = _transactions.where((tx) {
//       DateTime date = tx.timestamp.toDate();
//       return date.isAfter(_startDate.subtract(Duration(days: 1))) &&
//           date.isBefore(_endDate.add(Duration(days: 1))) &&
//           tx.role == 'seller' &&
//           tx.quantity > 0;
//     }).toList();

//     for (var tx in transactionsInRange) {
//       DateTime date = tx.timestamp.toDate();
//       DateTime dateKey = DateTime(date.year, date.month, date.day);
//       double amount = tx.price * tx.quantity;

//       _earningsOverTime.update(
//         dateKey,
//         (value) => value + amount,
//         ifAbsent: () => amount,
//       );
//     }

//     // Fill in missing dates with previous day's earnings
//     DateTime currentDate = DateTime(
//         _startDate.year, _startDate.month, _startDate.day); // Start of range
//     DateTime finalDate =
//         DateTime(_endDate.year, _endDate.month, _endDate.day); // End of range

//     double previousEarnings = 0.0;
//     while (!currentDate.isAfter(finalDate)) {
//       if (_earningsOverTime.containsKey(currentDate)) {
//         previousEarnings = _earningsOverTime[currentDate]!;
//       } else {
//         // If no earnings, carry forward the previous day's earnings
//         _earningsOverTime[currentDate] = previousEarnings;
//       }
//       currentDate = currentDate.add(Duration(days: 1));
//     }

//     // Sort the map by date
//     _earningsOverTime = Map.fromEntries(
//       _earningsOverTime.entries.toList()
//         ..sort((a, b) => a.key.compareTo(b.key)),
//     );

//     print('StatProvider: Earnings Over Time: $_earningsOverTime');
//   }

//   void _findMostSoldProduct() {
//     if (_transactions.isEmpty) {
//       _mostSoldProduct = null;
//       _mostSoldProductSoldQuantity = 0;
//       print('StatProvider: No transactions to determine most sold product.');
//       return;
//     }

//     Map<String, int> productSalesCount = {};

//     for (var tx in _transactions) {
//       if (tx.role != 'seller' || tx.quantity <= 0) continue;

//       String productId = tx.productId;
//       int quantity = tx.quantity;

//       productSalesCount.update(
//         productId,
//         (value) => value + quantity,
//         ifAbsent: () => quantity,
//       );
//     }

//     if (productSalesCount.isEmpty) {
//       _mostSoldProduct = null;
//       _mostSoldProductSoldQuantity = 0;
//       print(
//           'StatProvider: No valid transactions to determine most sold product.');
//       return;
//     }

//     String mostSoldProductId = productSalesCount.entries
//         .reduce((current, next) => current.value > next.value ? current : next)
//         .key;

//     // Use firstWhereOrNull from the collection package
//     _mostSoldProduct =
//         _userProducts.firstWhereOrNull((p) => p.id == mostSoldProductId);
//     _mostSoldProductSoldQuantity = productSalesCount[mostSoldProductId] ?? 0;

//     print(
//         'StatProvider: Most Sold Product ID: ${_mostSoldProduct?.id} with $_mostSoldProductSoldQuantity sales.');
//   }

//   void _computeProductStatistics() {
//     // Compute most clicked product
//     if (_userProducts.isNotEmpty) {
//       _mostClickedProduct = _userProducts.reduce((current, next) =>
//           (current.clickCount) > (next.clickCount) ? current : next);
//       print(
//           'StatProvider: Most Clicked Product ID: ${_mostClickedProduct?.id} with ${_mostClickedProduct?.clickCount} clicks.');

//       // Compute most favorited product
//       _mostFavoritedProduct = _userProducts.reduce((current, next) =>
//           (current.favoritesCount) > (next.favoritesCount) ? current : next);
//       print(
//           'StatProvider: Most Favorited Product ID: ${_mostFavoritedProduct?.id} with ${_mostFavoritedProduct?.favoritesCount} favorites.');

//       // Compute most added to cart product
//       _mostAddedToCartProduct = _userProducts.reduce((current, next) =>
//           (current.cartCount) > (next.cartCount) ? current : next);
//       print(
//           'StatProvider: Most Added to Cart Product ID: ${_mostAddedToCartProduct?.id} with ${_mostAddedToCartProduct?.cartCount} additions.');

//       // Compute highest rated product
//       _highestRatedProduct = _userProducts.reduce((current, next) =>
//           (current.averageRating) > (next.averageRating) ? current : next);
//       print(
//           'StatProvider: Highest Rated Product ID: ${_highestRatedProduct?.id} with rating ${_highestRatedProduct?.averageRating}.');
//     } else {
//       _mostClickedProduct = null;
//       _mostFavoritedProduct = null;
//       _mostAddedToCartProduct = null;
//       _highestRatedProduct = null;
//       print('StatProvider: No products to compute product statistics.');
//     }
//   }
// }

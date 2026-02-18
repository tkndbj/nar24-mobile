// import 'package:collection/collection.dart'; // For firstWhereOrNull
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:provider/provider.dart';
// // If your localization class is differently named, adjust the import:
// import '../../generated/l10n/app_localizations.dart';

// import '../../providers/stat_provider.dart';
// import '../../theme.dart'; // Import your theme file if needed
// import '../../widgets/stats/earnings_chart.dart';
// import '../../widgets/stats/most_sold_product_widget.dart';
// import '../../widgets/stats/product_stat_widget.dart';
// import '../../widgets/stats/stat_card.dart';

// import '../LIST-PRODUCT/list_product_screen.dart'; // Make sure you import this

// class SoldProductStatScreen extends StatelessWidget {
//   final String currentUserId; // The user to update if they choose VIP

//   const SoldProductStatScreen({
//     Key? key,
//     required this.currentUserId,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     // Retrieve jadeColor from the theme extension
//     final jadeColor = Theme.of(context).extension<CustomColors>()?.jadeColor ??
//         const Color(0xFF00A86B);

//     final statProvider = Provider.of<StatProvider>(context);
//     final loc = AppLocalizations.of(context); // For convenience

//     // Determine the currency based on transactions or default to 'TRY'
//     String currency = 'TRY';
//     if (statProvider.transactions.isNotEmpty) {
//       var firstTransaction = statProvider.transactions
//           .firstWhereOrNull((tx) => tx.currency.isNotEmpty);
//       if (firstTransaction != null) {
//         currency = firstTransaction.currency;
//       }
//     } else if (statProvider.userProducts.isNotEmpty) {
//       // If no transactions, use the first product's currency
//       var firstProduct = statProvider.userProducts
//           .firstWhereOrNull((prod) => prod.currency.isNotEmpty);
//       if (firstProduct != null) {
//         currency = firstProduct.currency;
//       }
//     }

//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//         title: Text(loc.title2),
//         actions: [
//           // Premium icon: opens the bottom sheet to become VIP
//           IconButton(
//             icon: Image.asset(
//               'assets/images/premium.png',
//               height: 24,
//               width: 24,
//             ),
//             onPressed: () {
//               _showPremiumBottomSheet(context);
//             },
//           ),
//           IconButton(
//             icon: const Icon(Icons.date_range),
//             onPressed: () async {
//               DateTimeRange? picked = await showDateRangePicker(
//                 context: context,
//                 firstDate: DateTime(2020),
//                 lastDate: DateTime.now(),
//                 initialDateRange: DateTimeRange(
//                   start: statProvider.startDate,
//                   end: statProvider.endDate,
//                 ),
//               );
//               if (picked != null) {
//                 await statProvider.updateDateRange(picked.start, picked.end);
//               }
//             },
//           ),
//         ],
//       ),

//       // If no transactions, show placeholder with GIF, text, and button
//       body: statProvider.transactions.isEmpty
//           ? Center(
//               child: SingleChildScrollView(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     // GIF
//                     Image.asset(
//                       'images/assets/stat.gif',
//                       width: 200,
//                       height: 200,
//                     ),
//                     const SizedBox(height: 24),
//                     // Placeholder text
//                     Padding(
//                       padding: const EdgeInsets.symmetric(horizontal: 24.0),
//                       child: Text(
//                         loc.noSalesYet, // "Currently you haven't made any sales..."
//                         textAlign: TextAlign.center,
//                         style: const TextStyle(
//                           fontFamily: 'Figtree',
//                           fontSize: 16,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 24),
//                     // "List a product" button
//                     ElevatedButton(
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: jadeColor, // Jade color
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         // You can set a fixed width if you'd like; this prevents full-width
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 32.0,
//                           vertical: 12.0,
//                         ),
//                       ),
//                       onPressed: () {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (_) => const ListProductScreen(),
//                           ),
//                         );
//                       },
//                       child: Text(
//                         loc.listAProduct, // "List a product"
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.w600,
//                           fontFamily: 'Figtree',
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             )
//           : SingleChildScrollView(
//               child: Column(
//                 children: [
//                   // Total earnings
//                   StatCard(
//                     title: loc.totalEarnings, // "Total Earnings"
//                     value: NumberFormat.simpleCurrency(name: currency)
//                         .format(statProvider.totalEarnings),
//                     valueColor: jadeColor, // Jade color for the price
//                   ),

//                   // Earnings chart
//                   EarningsChart(
//                     earningsOverTime: statProvider.earningsOverTime,
//                     startDate: statProvider.startDate,
//                     endDate: statProvider.endDate,
//                   ),

//                   // Most sold product
//                   if (statProvider.mostSoldProduct != null)
//                     MostSoldProductWidget(
//                       product: statProvider.mostSoldProduct!,
//                       soldQuantity: statProvider.mostSoldProductSoldQuantity,
//                     ),

//                   // Most clicked product
//                   if (statProvider.mostClickedProduct != null)
//                     ProductStatWidget(
//                       title: loc.mostClicked,
//                       product: statProvider.mostClickedProduct!,
//                       value: '${statProvider.mostClickedProduct!.clickCount}',
//                     ),

//                   // Most favorited product
//                   if (statProvider.mostFavoritedProduct != null)
//                     ProductStatWidget(
//                       title: loc.mostFavorited,
//                       product: statProvider.mostFavoritedProduct!,
//                       value:
//                           '${statProvider.mostFavoritedProduct!.favoritesCount}',
//                     ),

//                   // Most added to cart
//                   if (statProvider.mostAddedToCartProduct != null)
//                     ProductStatWidget(
//                       title: loc.mostAddedToCart,
//                       product: statProvider.mostAddedToCartProduct!,
//                       value:
//                           '${statProvider.mostAddedToCartProduct!.cartCount}',
//                     ),

//                   // Highest rated product
//                   if (statProvider.highestRatedProduct != null)
//                     ProductStatWidget(
//                       title: loc.highestRated,
//                       product: statProvider.highestRatedProduct!,
//                       value:
//                           '${statProvider.highestRatedProduct!.averageRating.toStringAsFixed(1)} ★',
//                     ),
//                 ],
//               ),
//             ),
//     );
//   }

//   /// Shows the premium bottom sheet with relevant info.
//   void _showPremiumBottomSheet(BuildContext context) {
//     final loc = AppLocalizations.of(context);

//     showModalBottomSheet(
//       context: context,
//       isScrollControlled:
//           true, // Makes the modal take full height if content is large
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
//       ),
//       builder: (BuildContext ctx) {
//         final jadeColor = Theme.of(ctx).extension<CustomColors>()?.jadeColor ??
//             const Color(0xFF00A86B);
//         return Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               // Premium icon at top
//               Image.asset(
//                 'assets/images/premium.png',
//                 width: 60,
//                 height: 60,
//               ),
//               const SizedBox(height: 16),
//               // Title text
//               Text(
//                 loc.becomeVipTitle,
//                 textAlign: TextAlign.center,
//                 style: const TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontFamily: 'Figtree',
//                   fontSize: 16,
//                 ),
//               ),
//               const SizedBox(height: 8),
//               // Subtitle text
//               Text(
//                 loc.becomeVipSubtitle,
//                 textAlign: TextAlign.center,
//                 style: const TextStyle(
//                   fontFamily: 'Figtree',
//                   fontSize: 14,
//                 ),
//               ),

//               const SizedBox(height: 16),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

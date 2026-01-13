// // lib/widgets/teras_app_bar.dart

// import 'dart:io';
// import 'package:firebase_auth/firebase_auth.dart'; // for current user id
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../../generated/l10n/app_localizations.dart';
// import '../../providers/teras_provider.dart';
// import '../../providers/search_history_provider.dart';
// import '../../models/product.dart';
// import '../../screens/product_detail_screen.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:go_router/go_router.dart';
// import '../../route_observer.dart'; // Import your global route observer
// // Import the language selector widget.
// import '../language_selector.dart';
// import '../product_card.dart';
// import 'dart:async';
// import 'package:posthog_flutter/posthog_flutter.dart';
// /// Note: This TerasAppBar is modified similarly to MarketAppBar.
// /// All additions (caching, horizontal most searched products section, etc.)
// /// have been applied, and the onPopInvokedWithResult callback now returns void.
// class MarketAppBar extends StatefulWidget implements PreferredSizeWidget {
//   final TextEditingController searchController;
//   final FocusNode searchFocusNode;
//   final VoidCallback onTakePhoto;
//   final VoidCallback onSelectFromAlbum;
//   final VoidCallback onSubmitSearch;

//   const MarketAppBar({
//     Key? key,
//     required this.searchController,
//     required this.searchFocusNode,
//     required this.onTakePhoto,
//     required this.onSelectFromAlbum,
//     required this.onSubmitSearch,
//   }) : super(key: key);

//   @override
//   State<MarketAppBar> createState() => _MarketAppBarState();

//   @override
//   Size get preferredSize => const Size.fromHeight(kToolbarHeight);
// }

// class _MarketAppBarState extends State<MarketAppBar>
//     with SingleTickerProviderStateMixin, RouteAware {
//   late OverlayEntry _overlayEntry;
//   bool _isOverlayOpen = false;
//   List<Map<String, dynamic>> _suggestions = [];
//   late AnimationController _animationController;
//   late Animation<Offset> _slideAnimation;
//   String _userId = 'anonymous';
//   bool _hasRecordedSearch = false;
//   String _lastRecordedTerm = '';
//   Timer? _debounce;
//   // --- Caching for most searched products ---
//   List<Map<String, dynamic>>? _cachedMostSearchedProducts;
//   DateTime? _cachedMostSearchedTime;

//   Future<List<Map<String, dynamic>>> _getCachedMostSearchedProducts() async {
//     const cacheDuration = Duration(minutes: 5);
//     if (_cachedMostSearchedProducts != null &&
//         _cachedMostSearchedTime != null &&
//         DateTime.now().difference(_cachedMostSearchedTime!) < cacheDuration) {
//       return _cachedMostSearchedProducts!;
//     }
//     _cachedMostSearchedProducts = await _fetchMostSearchedProducts();
//     _cachedMostSearchedTime = DateTime.now();
//     return _cachedMostSearchedProducts!;
//   }

//   Future<List<Map<String, dynamic>>> _fetchMostSearchedProducts() async {
//     final terasProvider = Provider.of<TerasProvider>(context, listen: false);
//     // Assumes fetchProducts returns all products.
//     List<Product> products = await terasProvider.fetchProducts();
//     // First, try to get products with dailyClickCount > 20.
//     List<Product> filtered =
//         products.where((p) => (p.dailyClickCount ?? 0) > 20).toList();
//     if (filtered.isNotEmpty) {
//       filtered.sort(
//           (a, b) => (b.dailyClickCount ?? 0).compareTo(a.dailyClickCount ?? 0));
//     } else {
//       products.sort((a, b) => (b.clickCount ?? 0).compareTo(a.clickCount ?? 0));
//       filtered = products;
//     }
//     // Ensure exactly 20 products.
//     if (filtered.length < 20) {
//       Set<String> existingIds = filtered.map((p) => p.id).toSet();
//       List<Product> additional =
//           products.where((p) => !existingIds.contains(p.id)).toList();
//       additional
//           .sort((a, b) => (b.clickCount ?? 0).compareTo(a.clickCount ?? 0));
//       filtered.addAll(additional);
//       filtered = filtered.take(20).toList();
//     } else {
//       filtered = filtered.take(20).toList();
//     }
//     final ownerIds = filtered.map((p) => p.ownerId).toSet();
//     final verifications =
//         await terasProvider.fetchOwnersVerificationStatus(ownerIds);
//     return filtered.map((product) {
//       final isVerified = verifications[product.ownerId] ?? false;
//       return {'product': product, 'isVerified': isVerified};
//     }).toList();
//   }

//   @override
//   void initState() {
//     super.initState();
//     widget.searchFocusNode.addListener(_handleFocusChange);
//     widget.searchController.addListener(_handleTextChange);
//     _animationController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 150),
//     );
//     _slideAnimation = Tween<Offset>(
//       begin: const Offset(0, 1.0),
//       end: Offset.zero,
//     ).animate(
//       CurvedAnimation(
//         parent: _animationController,
//         curve: Curves.easeOut,
//       ),
//     );
//     final User? user = FirebaseAuth.instance.currentUser;
//     _userId = user?.uid ?? 'anonymous';
//     Provider.of<SearchHistoryProvider>(context, listen: false)
//         .fetchSearchHistory(_userId);
//   }

//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     routeObserver.subscribe(this, ModalRoute.of(context)!);
//   }

 
//  @override
// void dispose() {
//   // Cancel the debounce timer if it's active.
//   _debounce?.cancel();

//   // Remove listeners, dispose animation controller, etc.
//   widget.searchFocusNode.removeListener(_handleFocusChange);
//   widget.searchController.removeListener(_handleTextChange);
//   _animationController.dispose();
//   routeObserver.unsubscribe(this);
//   super.dispose();
// }


//   @override
//   void didPopNext() {
//     widget.searchController.clear();
//     widget.searchFocusNode.unfocus();
//   }

//   @override
//   void didPushNext() {
//     widget.searchController.clear();
//     widget.searchFocusNode.unfocus();
//   }

//   void _handleFocusChange() {
//     if (widget.searchFocusNode.hasFocus) {
//       _openOverlay();
//       if (widget.searchController.text.isNotEmpty) {
//         _fetchAndSetSuggestions(widget.searchController.text);
//       }
//     } else {
//       _closeOverlay();
//     }
//   }

//   void _handleTextChange() {
//   // Cancel any existing timer.
//   if (_debounce?.isActive ?? false) _debounce!.cancel();

//   // Set a new timer.
//   _debounce = Timer(const Duration(milliseconds: 300), () {
//     // Make sure the widget is still in the tree.
//     if (!mounted) return;

//     // Mark that we haven't recorded a search yet.
//     // (So suffix icon / onSubmitted can record if needed.)
//     setState(() => _hasRecordedSearch = false);

//     // Now fetch suggestions after the user has paused typing.
//     _fetchAndSetSuggestions(widget.searchController.text);
//   });
// }


//   Future<void> _fetchAndSetSuggestions(String pattern) async {
//     final terasProvider = Provider.of<TerasProvider>(context, listen: false);
//     if (pattern.trim().isEmpty) {
//       setState(() => _suggestions = []);
//       _refreshOverlay();
//       return;
//     }
//     final rawProducts = await terasProvider.fetchSuggestions(pattern);
//     if (rawProducts.isEmpty) {
//       setState(() => _suggestions = []);
//       _refreshOverlay();
//       return;
//     }
//     final ownerIds = rawProducts.map((p) => p.ownerId).toSet();
//     final verifications =
//         await terasProvider.fetchOwnersVerificationStatus(ownerIds);
//     final results = rawProducts.map((prod) {
//       final bool isVerified = verifications[prod.ownerId] ?? false;
//       return {
//         'product': prod,
//         'isVerified': isVerified,
//       };
//     }).toList();
//     setState(() {
//       _suggestions = results;
//     });
//     _refreshOverlay();
//   }

//   void _openOverlay() {
//     if (_isOverlayOpen) return;
//     _overlayEntry = _createOverlayEntry();
//     Overlay.of(context).insert(_overlayEntry);
//     setState(() {
//       _isOverlayOpen = true;
//     });
//     _animationController.forward();
//   }

//   void _refreshOverlay() {
//     if (_isOverlayOpen) _overlayEntry.markNeedsBuild();
//   }

//   void _closeOverlay() {
//     if (!_isOverlayOpen) return;
//     _animationController.reverse().then((_) {
//       _overlayEntry.remove();
//       setState(() {
//         _isOverlayOpen = false;
//       });
//     });
//   }

//   OverlayEntry _createOverlayEntry() {
//     final appBarHeight =
//         widget.preferredSize.height + MediaQuery.of(context).padding.top;
//     final theme = Theme.of(context);
//     final isDark = theme.brightness == Brightness.dark;
//     return OverlayEntry(
//       builder: (context) {
//         return Positioned(
//           top: appBarHeight,
//           left: 0,
//           right: 0,
//           bottom: 0,
//           child: SlideTransition(
//             position: _slideAnimation,
//             child: Material(
//               color: theme.scaffoldBackgroundColor,
//               child: GestureDetector(
//                 onTap: () => widget.searchFocusNode.unfocus(),
//                 behavior: HitTestBehavior.translucent,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // >>> Search History Section
//                     Consumer<SearchHistoryProvider>(
//                       builder: (context, searchHistoryProvider, _) {
//                         final history = searchHistoryProvider.searchEntries;
//                         if (history.isEmpty) return const SizedBox(height: 16);
//                         return Container(
//                           height: 32,
//                           margin: const EdgeInsets.symmetric(
//                               horizontal: 8, vertical: 8),
//                           child: ListView.builder(
//                             scrollDirection: Axis.horizontal,
//                             itemCount: history.length,
//                             itemBuilder: (context, index) {
//                               final entry = history[index];
//                               return InkWell(
//                                 onTap: () {
//                                   widget.searchFocusNode.unfocus();
//                                   _closeOverlay();
//                                   Posthog().capture(
//     eventName: 'TerasSearchHistorySelected',
//     properties: {
//       'searchTerm': entry.searchTerm,
//     },
//   );
//                                   context.push('/search_results',
//                                       extra: {'query': entry.searchTerm});
//                                 },
//                                 child: Container(
//                                   margin: const EdgeInsets.only(right: 8),
//                                   padding: const EdgeInsets.symmetric(
//                                       horizontal: 8, vertical: 4),
//                                   decoration: BoxDecoration(
//                                     color:
//                                         const Color.fromARGB(122, 66, 66, 66),
//                                     borderRadius: BorderRadius.circular(16),
//                                   ),
//                                   child: Row(
//                                     mainAxisSize: MainAxisSize.min,
//                                     children: [
//                                       const Icon(
//                                         Icons.history,
//                                         size: 16,
//                                         color: Colors.white,
//                                       ),
//                                       const SizedBox(width: 4),
//                                       Text(
//                                         entry.searchTerm,
//                                         style: const TextStyle(
//                                           color: Colors.white,
//                                           fontSize: 12,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               );
//                             },
//                           ),
//                         );
//                       },
//                     ),
//                     // >>> NEW: Most Searched Products Section (horizontally scrollable row)
//                     Container(
//                       height:
//                           300, // increased container height for better visibility
//                       child: FutureBuilder<List<Map<String, dynamic>>>(
//                         future: _getCachedMostSearchedProducts(),
//                         builder: (context, snapshot) {
//                           if (!snapshot.hasData) {
//                             return const Center(
//                                 child: CircularProgressIndicator());
//                           }
//                           final List<Map<String, dynamic>> mostSearched =
//                               snapshot.data!;
//                           return Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Padding(
//                                 padding: const EdgeInsets.all(8.0),
//                                 child: Text(
//                                   AppLocalizations.of(context)!
//                                       .mostSearchedProducts,
//                                   style: TextStyle(
//                                     fontSize: 16,
//                                     fontWeight: FontWeight.bold,
//                                     color: isDark ? Colors.white : Colors.black,
//                                   ),
//                                 ),
//                               ),
//                               Expanded(
//                                 child: SingleChildScrollView(
//                                   scrollDirection: Axis.horizontal,
//                                   child: Row(
//                                     children: mostSearched.map((map) {
//                                       final Product product =
//                                           map['product'] as Product;
//                                       final bool isVerified =
//                                           map['isVerified'] as bool;
//                                       final String labelText =
//                                           isVerified ? 'Ada Express' : 'Teras';
//                                       final List<Color> gradientColors =
//                                           isVerified
//                                               ? [Colors.orange, Colors.pink]
//                                               : [Colors.purple, Colors.pink];
//                                       return Padding(
//                                         padding: const EdgeInsets.symmetric(
//                                             horizontal: 8.0),
//                                         child: SizedBox(
//                                           width: 150,
//                                           child: Stack(
//                                             children: [
//                                               // Display the ProductCard with specified portraitImageHeight.
//                                               ProductCard(
//                                                 product: product,
//                                                 showExtraLabels: false,
//                                                 portraitImageHeight: 150,
//                                               ),
//                                               // Manually position a single extra label.
//                                               Positioned(
//                                                 top: 6,
//                                                 right: 30,
//                                                 child: Container(
//                                                   padding: const EdgeInsets
//                                                       .symmetric(
//                                                       horizontal: 4,
//                                                       vertical: 2),
//                                                   decoration: BoxDecoration(
//                                                     gradient: LinearGradient(
//                                                         colors: gradientColors),
//                                                     borderRadius:
//                                                         BorderRadius.circular(
//                                                             4),
//                                                   ),
//                                                   child: Text(
//                                                     labelText,
//                                                     style: const TextStyle(
//                                                       color: Colors.white,
//                                                       fontSize: 10,
//                                                       fontWeight:
//                                                           FontWeight.bold,
//                                                     ),
//                                                   ),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                         ),
//                                       );
//                                     }).toList(),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           );
//                         },
//                       ),
//                     ),
//                     // >>> Suggestions Section: Only show suggestions if the search box is not empty.
//                     widget.searchController.text.trim().isNotEmpty
//                         ? Expanded(
//                             child: ListView.builder(
//                               itemCount: _suggestions.length,
//                               itemBuilder: (context, index) {
//                                 final map = _suggestions[index];
//                                 final product = map['product'] as Product;
//                                 final isVerified = map['isVerified'] as bool;
//                                 final hasImages = (product.imageUrls != null &&
//                                     product.imageUrls!.isNotEmpty);
//                                 final firstImage =
//                                     hasImages ? product.imageUrls![0] : null;
//                                 final labelText =
//                                     isVerified ? 'Ada Express' : 'Teras';
//                                 final gradientColors = isVerified
//                                     ? [Colors.orange, Colors.pink]
//                                     : [Colors.purple, Colors.pink];
//                                 return InkWell(
//                                   onTap: () {
//                                     widget.searchFocusNode.unfocus();
//                                     Posthog().capture(
//     eventName: 'TerasScreenSuggestionSelected',
//     properties: {
//       'productId': product.id,
//       'productName': product.productName,
//       'queryUsed': widget.searchController.text.trim(),
//     },
//   );
//                                     final route = MaterialPageRoute(
//                                       builder: (_) => ProductDetailScreen(
//                                         product: product,
//                                         productId: product.id,
//                                       ),
//                                     );
//                                     Navigator.of(context).push(route);
//                                   },
//                                   child: ListTile(
//                                     leading: firstImage != null
//                                         ? Image.network(
//                                             firstImage,
//                                             width: 40,
//                                             height: 40,
//                                             fit: BoxFit.cover,
//                                           )
//                                         : Icon(
//                                             Icons.image_not_supported,
//                                             color: isDark
//                                                 ? Colors.white
//                                                 : Colors.black,
//                                           ),
//                                     title: Text(
//                                       product.productName,
//                                       style: TextStyle(
//                                         color: isDark
//                                             ? Colors.white
//                                             : Colors.black,
//                                       ),
//                                     ),
//                                     trailing: Container(
//                                       padding: const EdgeInsets.symmetric(
//                                         horizontal: 8,
//                                         vertical: 4,
//                                       ),
//                                       decoration: BoxDecoration(
//                                         gradient: LinearGradient(
//                                           colors: gradientColors,
//                                         ),
//                                         borderRadius: BorderRadius.circular(6),
//                                       ),
//                                       child: Text(
//                                         labelText,
//                                         style: const TextStyle(
//                                           color: Colors.white,
//                                           fontWeight: FontWeight.bold,
//                                         ),
//                                       ),
//                                     ),
//                                   ),
//                                 );
//                               },
//                             ),
//                           )
//                         : const SizedBox.shrink(),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Future<bool> _handleWillPop() async {
//     if (_isOverlayOpen) {
//       widget.searchController.clear();
//       widget.searchFocusNode.unfocus();
//       _closeOverlay();
//       return false;
//     }
//     return true;
//   }

//   void _showCameraOptions() {
//     final l10n = AppLocalizations.of(context)!;
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     showModalBottomSheet(
//       context: context,
//       builder: (context) {
//         return Wrap(
//           children: [
//             ListTile(
//               leading: Icon(
//                 Icons.camera_alt,
//                 color: isDark ? Colors.white : Colors.black,
//               ),
//               title: Text(
//                 l10n.takePhoto,
//                 style: TextStyle(
//                   color: isDark ? Colors.white : Colors.black,
//                 ),
//               ),
//               onTap: () {
//                 Navigator.of(context).pop();
//                 widget.onTakePhoto();
//               },
//             ),
//             ListTile(
//               leading: Icon(
//                 Icons.photo_album,
//                 color: isDark ? Colors.white : Colors.black,
//               ),
//               title: Text(
//                 l10n.selectFromAlbum,
//                 style: TextStyle(
//                   color: isDark ? Colors.white : Colors.black,
//                 ),
//               ),
//               onTap: () {
//                 Navigator.of(context).pop();
//                 widget.onSelectFromAlbum();
//               },
//             ),
//             ListTile(
//               leading: Icon(
//                 Icons.cancel,
//                 color: isDark ? Colors.white : Colors.black,
//               ),
//               title: Text(
//                 l10n.cancel,
//                 style: TextStyle(
//                   color: isDark ? Colors.white : Colors.black,
//                 ),
//               ),
//               onTap: () {
//                 Navigator.of(context).pop();
//               },
//             ),
//           ],
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final l10n = AppLocalizations.of(context)!;
//     final terasProvider = Provider.of<TerasProvider>(context, listen: false);
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     return PopScope<Object?>(
//       canPop: true,
//       onPopInvokedWithResult: (bool didPop, Object? result) async {
//         if (_isOverlayOpen) {
//           widget.searchController.clear();
//           widget.searchFocusNode.unfocus();
//           _closeOverlay();
//         }
//         // Do nothing further.
//       },
//       child: AppBar(
//         backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//         automaticallyImplyLeading: false,
//         titleSpacing: 0.0,
//         toolbarHeight: kToolbarHeight,
//         flexibleSpace: SafeArea(
//           child: MediaQuery(
//             data: MediaQuery.of(context).copyWith(
//               textScaler: TextScaler.noScaling,
//             ),
//             child: Row(
//               children: [
//                 ValueListenableBuilder<bool>(
//                   valueListenable: terasProvider.isSidebarExpanded,
//                   builder: (_, isExpanded, __) {
//                     final icon = _isOverlayOpen
//                         ? Icons.arrow_back
//                         : (isExpanded ? Icons.arrow_back : Icons.menu);
//                     return IconButton(
//                       icon: Icon(
//                         icon,
//                         color: isDark ? Colors.white : Colors.black,
//                       ),
//                       onPressed: () {
//                         if (_isOverlayOpen) {
//                           widget.searchController.clear();
//                           widget.searchFocusNode.unfocus();
//                           _closeOverlay();
//                         } else {
//                           terasProvider.toggleSidebar();
//                         }
//                       },
//                     );
//                   },
//                 ),
//                 // The search box.
//                 Expanded(
//                   child: Container(
//                     margin: const EdgeInsets.only(right: 4.0),
//                     height: 40,
//                     decoration: BoxDecoration(
//                       color: Colors.white.withAlpha(25),
//                       border: Border.all(color: Colors.grey.withAlpha(128)),
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: TextField(
//                       controller: widget.searchController,
//                       focusNode: widget.searchFocusNode,
//                       textAlignVertical: TextAlignVertical.center,
//                       style: TextStyle(
//                         color: isDark ? Colors.white : Colors.black,
//                       ),
//                       decoration: InputDecoration(
//                         hintText: l10n.searchProducts,
//                         hintStyle: TextStyle(
//                           fontSize: 14,
//                           color: isDark
//                               ? Colors.white.withAlpha(179)
//                               : Colors.black.withAlpha(179),
//                         ),
//                         border: InputBorder.none,
//                         isDense: true,
//                         contentPadding: const EdgeInsets.symmetric(
//                           horizontal: 12,
//                           vertical: 12,
//                         ),
//                         prefixIcon: IconButton(
//                           icon: Icon(
//                             Icons.camera_alt,
//                             color: isDark ? Colors.white : Colors.black,
//                           ),
//                           onPressed: _showCameraOptions,
//                         ),
//                         suffixIcon: IconButton(
//                           icon: Icon(
//                             Icons.search,
//                             color: isDark ? Colors.white : Colors.black,
//                           ),
//                           onPressed: () {
//                             if (!_hasRecordedSearch) {
//                               widget.onSubmitSearch();
//                               widget.searchFocusNode.unfocus();
//                               final term = widget.searchController.text;
//                               Posthog().capture(
//         eventName: 'TerasScreenSearchExecuted',
//         properties: {
//           'searchTerm': term.trim(),
//         },
//       );
//                               if (term.trim().isNotEmpty &&
//                                   term != _lastRecordedTerm) {
//                                 Provider.of<TerasProvider>(context,
//                                         listen: false)
//                                     .recordSearchTerm(term);
//                                 _lastRecordedTerm = term;
//                                 widget.searchController.clear();
//                                 _hasRecordedSearch = true;
//                               }
//                             }
//                           },
//                         ),
//                       ),
//                       onSubmitted: (value) {
//                         if (!_hasRecordedSearch) {
//                           terasProvider.setSearchTerm(value);
//                           widget.onSubmitSearch();
//                           widget.searchFocusNode.unfocus();
//                           Posthog().capture(
//       eventName: 'TerasScreenSearchExecuted',
//       properties: {
//         'searchTerm': value.trim(),
//       },
//     );
//                           if (value.trim().isNotEmpty &&
//                               value != _lastRecordedTerm) {
//                             Provider.of<TerasProvider>(context, listen: false)
//                                 .recordSearchTerm(value);
//                             _lastRecordedTerm = value;
//                             widget.searchController.clear();
//                             _hasRecordedSearch = true;
//                           }
//                         }
//                       },
//                       onChanged: (value) {
//                         terasProvider.setSearchTerm(value);
//                         _hasRecordedSearch = false;
//                       },
//                     ),
//                   ),
//                 ),
//                 Padding(
//                   padding: const EdgeInsets.only(right: 8.0),
//                   child: LanguageSelector(
//                     iconColor: isDark ? Colors.white : Colors.black,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../widgets/product_card_4.dart';

class ArchivedProductsScreen extends StatefulWidget {
  const ArchivedProductsScreen({super.key});

  @override
  State<ArchivedProductsScreen> createState() => _ArchivedProductsScreenState();
}

class _ArchivedProductsScreenState extends State<ArchivedProductsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final ValueNotifier<List<Product>> _pausedProductsNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Product>> _filteredProductsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _isLoadingMoreNotifier = ValueNotifier(false);
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier('');

  bool _hasMoreProducts = true;
  DocumentSnapshot? _lastDoc;
  Timer? _debounce;

  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _loadPausedProducts();
    _setupScrollListener();
    _setupSearchListener();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _pausedProductsNotifier.dispose();
    _filteredProductsNotifier.dispose();
    _isLoadingNotifier.dispose();
    _isLoadingMoreNotifier.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 600) {
        if (!_isLoadingMoreNotifier.value &&
            _hasMoreProducts &&
            _searchQueryNotifier.value.isEmpty) {
          _loadMoreProducts();
        }
      }
    });
  }

  void _setupSearchListener() {
    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _searchQueryNotifier.value = _searchController.text.trim();
          _filterProducts();
        }
      });
    });
  }

  Future<void> _loadPausedProducts() async {
    if (!mounted) return;

    final uid = _currentUser?.uid;
    if (uid == null) {
      _isLoadingNotifier.value = false;
      return;
    }

    _isLoadingNotifier.value = true;

    try {
      Query query = _firestore
          .collection('paused_products')
          .where('userId', isEqualTo: uid)
          .orderBy('lastModified', descending: true)
          .limit(_pageSize);

      final snapshot = await query.get();

      if (mounted) {
        final products =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

        _pausedProductsNotifier.value = products;
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreProducts = snapshot.docs.length == _pageSize;

        _filterProducts();
      }
    } catch (e) {
      debugPrint('Error loading paused products: $e');
      if (mounted) {
        _showErrorSnackbar(AppLocalizations.of(context).errorLoadingProducts);
      }
    } finally {
      if (mounted) {
        _isLoadingNotifier.value = false;
      }
    }
  }

  Future<void> _loadMoreProducts() async {
    if (!mounted || _lastDoc == null || !_hasMoreProducts) return;

    final uid = _currentUser?.uid;
    if (uid == null) return;

    _isLoadingMoreNotifier.value = true;

    try {
      Query query = _firestore
          .collection('paused_products')
          .where('userId', isEqualTo: uid)
          .orderBy('lastModified', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize);

      final snapshot = await query.get();

      if (mounted) {
        final newProducts =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

        final currentProducts =
            List<Product>.from(_pausedProductsNotifier.value);
        currentProducts.addAll(newProducts);
        _pausedProductsNotifier.value = currentProducts;

        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreProducts = snapshot.docs.length == _pageSize;

        _filterProducts();
      }
    } catch (e) {
      debugPrint('Error loading more products: $e');
    } finally {
      if (mounted) {
        _isLoadingMoreNotifier.value = false;
      }
    }
  }

  void _filterProducts() {
    final query = _searchQueryNotifier.value;

    if (query.isEmpty) {
      _filteredProductsNotifier.value =
          List.from(_pausedProductsNotifier.value);
    } else {
      _filteredProductsNotifier.value =
          _pausedProductsNotifier.value.where((product) {
        return product.productName
                .toLowerCase()
                .contains(query.toLowerCase()) ||
            (product.brandModel ?? '')
                .toLowerCase()
                .contains(query.toLowerCase()) ||
            (product.category ?? '')
                .toLowerCase()
                .contains(query.toLowerCase());
      }).toList();
    }
  }

  Future<void> _unarchiveProduct(String productId, String productName) async {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);

    final confirmed = await _showUnarchiveConfirmation(productName);
    if (!confirmed) return;

    if (!mounted) return;

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx;
        return _buildUnarchiveLoadingDialog(productName);
      },
    );

    try {
      // Move product from paused_products back to products
      final sourceRef = _firestore.collection('paused_products').doc(productId);
      final destRef = _firestore.collection('products').doc(productId);

      await _firestore.runTransaction((transaction) async {
        final sourceDoc = await transaction.get(sourceRef);
        if (!sourceDoc.exists) {
          throw Exception('Product not found in paused_products');
        }

        final data = sourceDoc.data()!;
        data['paused'] = false;
        data['lastModified'] = FieldValue.serverTimestamp();

        transaction.set(destRef, data);
        transaction.delete(sourceRef);
      });

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        final currentPaused = List<Product>.from(_pausedProductsNotifier.value);
        currentPaused.removeWhere((p) => p.id == productId);
        _pausedProductsNotifier.value = currentPaused;

        _filterProducts();

        _showSuccessSnackbar(l10n.productUnarchivedSuccess);
      }
    } catch (e) {
      debugPrint('Error unarchiving product: $e');

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        _showErrorSnackbar(l10n.productUnarchiveError);
      }
    }
  }

  Future<bool> _showUnarchiveConfirmation(String productName) async {
    if (!mounted) return false;

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.unarchive_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.unarchiveProduct,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF667EEA).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF667EEA),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF667EEA),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.unarchiveProductConfirmation,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF667EEA),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CupertinoButton(
                        color: const Color(0xFF667EEA),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.unarchive_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.unarchive,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  Widget _buildUnarchiveLoadingDialog(String productName) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              builder: (context, value, child) {
                return Transform.rotate(
                  angle: value * 2 * 3.14159,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.unarchive_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              l10n.unarchivingProduct,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              productName,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 8,
                width: double.infinity,
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 2),
                  builder: (context, value, child) {
                    return LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF667EEA),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF38A169),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade500,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _navigateToUpdateProduct(Product product) {
    context.push(
      '/list-product',
      extra: {
        'existingProduct': product,
        'isFromArchivedCollection': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1C1A29)
          : const Color.fromARGB(255, 244, 244, 244),
      appBar: _buildAppBar(l10n, isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildInfoSection(l10n, isDark),
            _buildSearchBar(l10n, isDark),
            Expanded(
              child: _buildProductsList(l10n, isDark),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
      title: Text(
        l10n.archivedProducts,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: isDark ? Colors.white : Colors.black,
        ),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildInfoSection(AppLocalizations l10n, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2A2D3A), const Color(0xFF1F1F2E)]
              : [Colors.orange.shade50, Colors.orange.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.archive_rounded,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.archivedProductsManager,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.archivedProductsDescription,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            child: Icon(
              Icons.search_rounded,
              size: 18,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          suffixIcon: ValueListenableBuilder<String>(
            valueListenable: _searchQueryNotifier,
            builder: (context, query, _) {
              return query.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _searchQueryNotifier.value = '';
                        _filterProducts();
                      },
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade500,
                        ),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.archive_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                    );
            },
          ),
          hintText: l10n.searchArchivedProducts,
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          filled: true,
          fillColor: isDark ? const Color(0xFF2A2D3A) : Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.orange,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductsList(AppLocalizations l10n, bool isDark) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoadingNotifier,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return _buildShimmerGrid(isDark);
        }

        return ValueListenableBuilder<List<Product>>(
          valueListenable: _filteredProductsNotifier,
          builder: (context, filteredProducts, _) {
            if (filteredProducts.isEmpty) {
              return _buildEmptyState(l10n, isDark);
            }

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Results count header for search
                ValueListenableBuilder<String>(
                  valueListenable: _searchQueryNotifier,
                  builder: (context, searchQuery, _) {
                    if (searchQuery.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }

                    return SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search_rounded,
                              size: 16,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.searchResultsCount(
                                  filteredProducts.length.toString()),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 6.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = filteredProducts[index];
                        final productId = product.id;
                        final imageUrl = product.imageUrls.isNotEmpty
                            ? product.imageUrls[0]
                            : '';

                        return RepaintBoundary(
                          key: ValueKey('archived_$productId'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: _ArchivedProductCard(
                              product: product,
                              productId: productId,
                              imageUrl: imageUrl,
                              l10n: l10n,
                              isDark: isDark,
                              onUnarchive: () => _unarchiveProduct(
                                  productId, product.productName),
                              onUpdate: () => _navigateToUpdateProduct(product),
                            ),
                          ),
                        );
                      },
                      childCount: filteredProducts.length,
                      findChildIndexCallback: (Key key) {
                        if (key is ValueKey<String>) {
                          final valueKey = key.value;
                          if (valueKey.startsWith('archived_')) {
                            final productId = valueKey.substring(9);
                            final index = filteredProducts
                                .indexWhere((p) => p.id == productId);
                            return index >= 0 ? index : null;
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ),

                // Loading more indicator
                ValueListenableBuilder<bool>(
                  valueListenable: _isLoadingMoreNotifier,
                  builder: (context, isLoadingMore, _) {
                    return ValueListenableBuilder<String>(
                      valueListenable: _searchQueryNotifier,
                      builder: (context, searchQuery, _) {
                        if (!isLoadingMore || searchQuery.isNotEmpty) {
                          return const SliverToBoxAdapter(
                              child: SizedBox.shrink());
                        }

                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.orange,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShimmerGrid(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
                childCount: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    return ValueListenableBuilder<String>(
      valueListenable: _searchQueryNotifier,
      builder: (context, searchQuery, _) {
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.withOpacity(0.1),
                          Colors.orange.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.archive_rounded,
                      size: 80,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? l10n.noArchivedProductsFound
                        : l10n.noArchivedProducts,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    searchQuery.isNotEmpty
                        ? l10n.tryDifferentSearchTerm
                        : l10n.archivedProductsEmptyDescription,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.white30 : Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ArchivedProductCard extends StatelessWidget {
  final Product product;
  final String productId;
  final String imageUrl;
  final AppLocalizations l10n;
  final bool isDark;
  final VoidCallback onUnarchive;
  final VoidCallback onUpdate;

  const _ArchivedProductCard({
    required this.product,
    required this.productId,
    required this.imageUrl,
    required this.l10n,
    required this.isDark,
    required this.onUnarchive,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAdminArchived = product.archivedByAdmin == true;
    final bool needsUpdate = product.needsUpdate == true;
    final String? archiveReason = product.archiveReason;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey[200]!,
            blurRadius: 6,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
        border: isAdminArchived
            ? Border.all(
                color:
                    needsUpdate ? Colors.orange.shade400 : Colors.red.shade300,
                width: 1.5,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin Archive Banner
          if (isAdminArchived)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: needsUpdate ? Colors.orange.shade50 : Colors.red.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    needsUpdate
                        ? Icons.update_rounded
                        : Icons.admin_panel_settings_rounded,
                    size: 16,
                    color: needsUpdate
                        ? Colors.orange.shade700
                        : Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      needsUpdate
                          ? l10n.productNeedsUpdate ?? 'Güncelleme Gerekli'
                          : l10n.archivedByAdmin ??
                              'Admin tarafından arşivlendi',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: needsUpdate
                            ? Colors.orange.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Archive Reason Box
          if (isAdminArchived &&
              archiveReason != null &&
              archiveReason.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.shade200,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.message_rounded,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.adminMessage ?? 'Admin Mesajı',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    archiveReason,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),

          // Product Card Content
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      context.push('/product_detail/$productId');
                    },
                    child: ProductCard4(
                      key: ValueKey(productId),
                      imageUrl: imageUrl,
                      colorImages: product.colorImages,
                      selectedColor: null,
                      productName: product.productName.isNotEmpty
                          ? product.productName
                          : l10n.unnamedProduct,
                      brandModel: product.brandModel ?? '',
                      price: product.price,
                      currency: product.currency,
                      averageRating: product.averageRating,
                      productId: productId,
                      originalPrice: product.originalPrice,
                      discountPercentage: product.discountPercentage,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Action Button Column
                Column(
                  children: [
                    // Update Button (for needsUpdate products)
                    if (needsUpdate)
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF8C00), Color(0xFFFF6B00)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: TextButton(
                          onPressed: onUpdate,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: const StadiumBorder(),
                            backgroundColor: Colors.transparent,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.update ?? 'Güncelle',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Unarchive Button (only for non-admin archived products)
                    if (!isAdminArchived)
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: TextButton(
                          onPressed: onUnarchive,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            shape: const StadiumBorder(),
                            backgroundColor: Colors.transparent,
                            minimumSize: const Size(0, 24),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            l10n.unarchive,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                    // Locked indicator for admin archived (without needsUpdate)
                    if (isAdminArchived && !needsUpdate)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Tooltip(
                          message: l10n.contactSupportToUnarchive ??
                              'Arşivden çıkarmak için destek ile iletişime geçin',
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              color: Colors.red.shade400,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

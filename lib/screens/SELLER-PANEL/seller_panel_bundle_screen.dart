import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/bundle.dart';
import '../../providers/seller_panel_provider.dart';
import '../../generated/l10n/app_localizations.dart';
import 'seller_panel_create_bundle_screen.dart';
import 'seller_panel_edit_bundle_screen.dart';

class SellerPanelBundleScreen extends StatefulWidget {
  const SellerPanelBundleScreen({super.key});

  @override
  State<SellerPanelBundleScreen> createState() =>
      _SellerPanelBundleScreenState();
}

class _SellerPanelBundleScreenState extends State<SellerPanelBundleScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Bundle> _bundles = [];
  bool _isLoadingBundles = true;

  // Cache for bundle statistics (how many bundles each product is in)
  final Map<String, int> _bundleStats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBundles();
    });
  }

  Future<void> _loadBundles() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shopId = provider.selectedShop?.id;

    if (shopId == null) {
      setState(() => _isLoadingBundles = false);
      return;
    }

    setState(() => _isLoadingBundles = true);

    try {
      final snapshot = await _firestore
          .collection('bundles')
          .where('shopId', isEqualTo: shopId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      _bundles = snapshot.docs.map((doc) => Bundle.fromDocument(doc)).toList();

      // Calculate bundle statistics - count how many bundles each product is in
      _bundleStats.clear();
      for (var bundle in _bundles) {
        for (var product in bundle.products) {
          _bundleStats[product.productId] =
              (_bundleStats[product.productId] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('Error loading bundles: $e');
    } finally {
      setState(() => _isLoadingBundles = false);
    }
  }

  void _navigateToCreateBundle() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SellerPanelCreateBundleScreen(),
      ),
    ).then((result) {
      if (result == true) {
        _loadBundles();
      }
    });
  }

  void _navigateToEditBundle(Bundle bundle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SellerPanelEditBundleScreen(
          bundle: bundle,
        ),
      ),
    ).then((_) {
      _loadBundles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(l10n, isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(l10n, isDark),
            Expanded(
              child: _buildBundlesTab(l10n, isDark),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1A1B23) : Colors.white,
      foregroundColor: isDark ? Colors.white : const Color(0xFF1A202C),
      title: Text(
        l10n.productBundles,
        style: GoogleFonts.figtree(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A202C),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.activeBundlesCount(_bundles.length),
              style: GoogleFonts.figtree(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A202C),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _navigateToCreateBundle,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              l10n.createBundle,
              style: GoogleFonts.figtree(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBundlesTab(AppLocalizations l10n, bool isDark) {
    if (_isLoadingBundles) {
      return _buildLoadingList(isDark);
    }

    if (_bundles.isEmpty) {
      return _buildEmptyState(
        l10n.noActiveBundles,
        l10n.createProductBundlesToOfferSpecialPrices,
        isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bundles.length,
      itemBuilder: (context, index) {
        return _buildBundleCard(_bundles[index], isDark, l10n);
      },
    );
  }

  Widget _buildBundleCard(Bundle bundle, bool isDark, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1B23), const Color(0xFF2D3748)]
              : [Colors.white, const Color(0xFFFAFBFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF38A169).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _navigateToEditBundle(bundle),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_rounded,
                      color: const Color(0xFF667EEA),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.productCountBundle(bundle.productCount),
                        style: GoogleFonts.figtree(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A202C),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: isDark
                          ? const Color(0xFF718096)
                          : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${bundle.totalOriginalPrice.toStringAsFixed(2)} ${bundle.currency}',
                      style: GoogleFonts.figtree(
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFFA0AAB8)
                            : const Color(0xFF64748B),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${bundle.totalBundlePrice.toStringAsFixed(2)} ${bundle.currency}',
                      style: GoogleFonts.figtree(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF667EEA),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38A169).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '-${bundle.discountPercentage.toStringAsFixed(0)}%',
                        style: GoogleFonts.figtree(
                          color: const Color(0xFF38A169),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.productsColon,
                  style: GoogleFonts.figtree(
                    color: isDark
                        ? const Color(0xFFA0AAB8)
                        : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                ...bundle.products.take(3).map((product) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Color(0xFF667EEA),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              product.productName,
                              style: GoogleFonts.figtree(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFFA0AAB8)
                                    : const Color(0xFF4A5568),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                if (bundle.products.length > 3) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.moreProductsCount(bundle.products.length - 3),
                    style: GoogleFonts.figtree(
                      color: const Color(0xFF667EEA),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) => _buildSkeletonCard(isDark),
    );
  }

  Widget _buildSkeletonCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 120,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 16,
              width: 150,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF4A5568) : const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF4A5568) : const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 14,
              width: 200,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF4A5568) : const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF667EEA).withOpacity(0.1),
                    const Color(0xFF764BA2).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                size: 48,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.figtree(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? const Color(0xFFA0AAB8) : const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.figtree(
                fontSize: 13,
                color:
                    isDark ? const Color(0xFF718096) : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

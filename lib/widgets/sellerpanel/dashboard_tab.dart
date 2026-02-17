import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../constants/region.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../screens/SELLER-PANEL/ads_screen.dart';
import '../../screens/PAYMENT-RECEIPT/dynamic_payment_screen.dart';
import 'dart:async';

/// Phone number formatter for Turkish format: (5XX) XXX XX XX
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited =
        digitsOnly.length > 10 ? digitsOnly.substring(0, 10) : digitsOnly;

    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i == 0) buffer.write('(');
      buffer.write(limited[i]);
      if (i == 2) buffer.write(') ');
      if (i == 5) buffer.write(' ');
      if (i == 7) buffer.write(' ');
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Turkish IBAN formatter: TR + 24 digits, formatted as TR## #### #### #### #### #### ##
class _TurkishIbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String cleaned =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (cleaned.startsWith('TR')) {
      cleaned = cleaned.substring(2);
    }

    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    final limited =
        digitsOnly.length > 24 ? digitsOnly.substring(0, 24) : digitsOnly;

    final buffer = StringBuffer('TR');
    for (int i = 0; i < limited.length; i++) {
      if (i == 2 || i == 6 || i == 10 || i == 14 || i == 18 || i == 22) {
        buffer.write(' ');
      }
      buffer.write(limited[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({Key? key}) : super(key: key);

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _sellerInfo;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _ibanOwnerNameController =
      TextEditingController();
  final TextEditingController _ibanOwnerSurnameController =
      TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  String? _selectedRegion;

  List<AdSubmission> _pendingPaymentAds = [];
  StreamSubscription<QuerySnapshot>? _pendingAdsSubscription;

  bool _isDataLoaded = false;
  late Future<void> _initialLoadFuture;
  String? _currentShopId;

  /// Format stored phone "05XXXXXXXXX" to display format "(5XX) XXX XX XX"
  String _formatPhoneForDisplay(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    final digits =
        digitsOnly.startsWith('0') ? digitsOnly.substring(1) : digitsOnly;
    if (digits.length != 10) return phone;
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)} ${digits.substring(6, 8)} ${digits.substring(8, 10)}';
  }

  /// Format stored IBAN to display format "TR## #### #### #### #### #### ##"
  String _formatIbanForDisplay(String iban) {
    final cleaned = iban.toUpperCase().replaceAll(' ', '');
    if (cleaned.length != 26 || !cleaned.startsWith('TR')) return iban;
    final buffer = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      if (i == 4 || i == 8 || i == 12 || i == 16 || i == 20 || i == 24) {
        buffer.write(' ');
      }
      buffer.write(cleaned[i]);
    }
    return buffer.toString();
  }

  /// Checks if the current user has only viewer role for the selected shop.
  /// Returns true if user is a viewer, false otherwise.
  bool _isCurrentUserViewer(DocumentSnapshot? selectedShop) {
    if (selectedShop == null) return false;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return false;

    final shopData = selectedShop.data() as Map<String, dynamic>?;
    if (shopData == null) return false;

    final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
    return viewers.contains(currentUserId);
  }

  @override
  void initState() {
    super.initState();

    // Cache the initial loading future.
    _initialLoadFuture = _loadDataIfNeeded();
  }

  // Replace _loadDataIfNeeded with:
  Future<void> _loadDataIfNeeded([String? shopId]) async {
    if (!_isDataLoaded || shopId != _currentShopId) {
      _currentShopId = shopId;
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);

      // Parallel loading with staggered priorities
      final futures = <Future>[];

      // High priority - visible immediately
      futures.add(_fetchSellerInfoIfNeeded());

      // Medium priority - visible soon
      if (provider.cachedMetrics == null) {
        futures.add(provider.getMetrics(forceRefresh: true).catchError((e) {
          debugPrint('Metrics fetch error: $e');
        }));
      }

      // Low priority - background
      futures.add(Future.delayed(
        const Duration(milliseconds: 100),
        () => provider.fetchActiveCampaigns(),
      ).catchError((e) {
        debugPrint('Campaign fetch error: $e');
      }));

      // Don't wait for all - update UI as data arrives
      Future.wait(futures, eagerError: false).then((_) {
        if (mounted) {
          setState(() {
            _isDataLoaded = true;
          });
        }
      });

      // Listen for pending ad payments
      _pendingAdsSubscription?.cancel();
      final shopDoc = provider.selectedShop;
      if (shopDoc != null) {
        _pendingAdsSubscription = FirebaseFirestore.instance
            .collection('ad_submissions')
            .where('shopId', isEqualTo: shopDoc.id)
            .where('status', isEqualTo: 'approved')
            .orderBy('reviewedAt', descending: true)
            .limit(5)
            .snapshots()
            .listen((snapshot) {
          if (mounted) {
            setState(() {
              _pendingPaymentAds = snapshot.docs
                  .map((doc) => AdSubmission.fromDocument(doc))
                  .where((ad) => ad.paymentLink != null)
                  .toList();
            });
          }
        });
      }

      // Return immediately for first paint
      return;
    }
  }

  @override
  void dispose() {
    _pendingAdsSubscription?.cancel();
    _phoneController.dispose();
    _addressController.dispose();
    _ibanOwnerNameController.dispose();
    _ibanOwnerSurnameController.dispose();
    _ibanController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Widget _buildPendingAdPaymentBanners() {
    if (_pendingPaymentAds.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final isViewer = _isCurrentUserViewer(provider.selectedShop);
    if (isViewer) return const SizedBox.shrink();

    final adTypeLabels = {
      AdType.topBanner: l10n.topBanner,
      AdType.thinBanner: l10n.thinBanner,
      AdType.marketBanner: l10n.marketBanner,
    };

    return Column(
      children: _pendingPaymentAds.map((ad) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E1E2E), const Color(0xFF2A2040)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFF5F3FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF667EEA).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pendingPayment,
                      style: GoogleFonts.figtree(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${adTypeLabels[ad.adType] ?? ''} · ${ad.price?.toStringAsFixed(0) ?? '0'} TL',
                      style: GoogleFonts.figtree(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DynamicPaymentScreen(
                        submissionId: ad.id,
                        adType: ad.adType.name,
                        duration: ad.duration.name,
                        price: ad.price!,
                        imageUrl: ad.imageUrl,
                        shopName: ad.shopName,
                        paymentLink: ad.paymentLink!,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  l10n.proceedToPayment,
                  style: GoogleFonts.figtree(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Checks if the current shop has any listed products in shop_products collection.
  /// Returns true if products exist, false otherwise.
  /// On error, returns true to prevent accidental deletion.
  Future<bool> _shopHasListedProducts() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shop = provider.selectedShop;
    if (shop == null) return false;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_products')
          .where('shopId', isEqualTo: shop.id)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking shop products: $e');
      // Return true on error to be safe - prevents accidental deletion
      return true;
    }
  }

  Future<void> _deleteSellerInfo() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shop = provider.selectedShop;
    if (shop != null) {
      final ref = FirebaseFirestore.instance
          .collection('shops')
          .doc(shop.id)
          .collection('seller_info')
          .doc('info');
      await ref.delete();
      if (!mounted) return;
      setState(() {
        _sellerInfo = null;
        _phoneController.clear();
        _selectedRegion = null;
        _addressController.clear();
        _ibanOwnerNameController.clear();
        _ibanOwnerSurnameController.clear();
        _ibanController.clear();
        _regionController.clear();
      });
    }
  }

  Future<void> _fetchSellerInfoIfNeeded() async {
    if (!mounted) return;
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shop = provider.selectedShop;
    if (shop == null) return;
    final sellerInfoRef = FirebaseFirestore.instance
        .collection('shops')
        .doc(shop.id)
        .collection('seller_info')
        .doc('info');
    final docSnapshot = await sellerInfoRef.get();
    if (!mounted) return;
    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null) {
        setState(() {
          _sellerInfo = data;
          _phoneController.text = _formatPhoneForDisplay(data['phone'] ?? '');
          _selectedRegion = data['region'];
          _addressController.text = data['address'] ?? '';
          _ibanOwnerNameController.text = data['ibanOwnerName'] ?? '';
          _ibanOwnerSurnameController.text = data['ibanOwnerSurname'] ?? '';
          _ibanController.text = _formatIbanForDisplay(data['iban'] ?? '');
          _regionController.text = _selectedRegion ?? '';
        });
      }
    } else {
      setState(() {
        _sellerInfo = null;
      });
    }
  }

  Widget _buildModernMetricCard(
      String title, IconData icon, int value, List<Color> gradientColors,
      {bool isTablet = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Tablet: bigger icon, value and title for better visibility
    final double cardPadding = isTablet ? 10.0 : 12.0;
    final double iconPadding = isTablet ? 6.0 : 6.0;
    final double iconSize = isTablet ? 20.0 : 18.0;
    final double valueSize = isTablet ? 20.0 : 18.0;
    final double titleSize = isTablet ? 11.0 : 10.0;
    final double iconSpacing = isTablet ? 6.0 : 8.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isTablet ? 10 : 12),
      ),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 10 : 12),
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(isDark ? 0.1 : 0.2),
              Colors.transparent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(iconPadding),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(isTablet ? 6 : 8),
              ),
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
            SizedBox(height: iconSpacing),
            Text(
              value.toString(),
              style: GoogleFonts.figtree(
                fontWeight: FontWeight.bold,
                fontSize: valueSize,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: GoogleFonts.figtree(
                fontSize: titleSize,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;

    return Container(
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _showRegionPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    // Step 1: Show main regions
    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text(
          l10n.selectMainRegion ?? 'Select Main Region',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
            fontFamily: 'Figtree',
            fontSize: 16,
          ),
        ),
        actions: mainRegions.map((mainRegion) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showSubregionPicker(context, mainRegion);
            },
            child: Text(
              mainRegion,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
                fontSize: 16,
              ),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Figtree',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSubregionPicker(
      BuildContext context, String selectedMainRegion) async {
    final l10n = AppLocalizations.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final subregions = regionHierarchy[selectedMainRegion] ?? [];

    // Step 2: Show subregions for the selected main region
    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Column(
          children: [
            Text(
              selectedMainRegion,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Figtree',
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.selectSubregion ?? 'Select Subregion',
              style: TextStyle(
                color: isLight ? Colors.black54 : Colors.white70,
                fontWeight: FontWeight.w500,
                fontFamily: 'Figtree',
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          // Option to select the main region itself
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedRegion = selectedMainRegion;
                _regionController.text = selectedMainRegion;
              });
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_city_rounded,
                  color: const Color(0xFF00A86B),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '$selectedMainRegion (${l10n.mainRegion ?? 'Main Region'})',
                  style: TextStyle(
                    color: const Color(0xFF00A86B),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Figtree',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          if (subregions.isNotEmpty)
            Container(
              height: 1,
              color: isLight ? Colors.black12 : Colors.white24,
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),
          // Subregions
          ...subregions.map((subregion) {
            return CupertinoActionSheetAction(
              onPressed: () {
                setState(() {
                  _selectedRegion = subregion;
                  _regionController.text = subregion;
                });
                Navigator.pop(context);
              },
              child: Text(
                subregion,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                  fontSize: 16,
                ),
              ),
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            // Go back to main region selection
            _showRegionPicker(context);
          },
          child: Text(
            '← ${l10n.back ?? 'Back'}',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Figtree',
            ),
          ),
        ),
      ),
    );
  }

  void _showSellerInfoModal(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_sellerInfo != null) {
      _phoneController.text =
          _formatPhoneForDisplay(_sellerInfo!['phone'] ?? '');
      _selectedRegion = _sellerInfo!['region'];
      _addressController.text = _sellerInfo!['address'] ?? '';
      _ibanOwnerNameController.text = _sellerInfo!['ibanOwnerName'] ?? '';
      _ibanOwnerSurnameController.text = _sellerInfo!['ibanOwnerSurname'] ?? '';
      _ibanController.text = _formatIbanForDisplay(_sellerInfo!['iban'] ?? '');
      _regionController.text = _selectedRegion ?? '';
    } else {
      _phoneController.clear();
      _selectedRegion = null;
      _addressController.clear();
      _ibanOwnerNameController.clear();
      _ibanOwnerSurnameController.clear();
      _ibanController.clear();
      _regionController.clear();
    }

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => SellerInfoFormModal(
        sellerInfo: _sellerInfo,
        phoneController: _phoneController,
        addressController: _addressController,
        ibanOwnerNameController: _ibanOwnerNameController,
        ibanOwnerSurnameController: _ibanOwnerSurnameController,
        ibanController: _ibanController,
        regionController: _regionController,
        selectedRegion: _selectedRegion,
        onRegionSelected: (region) {
          setState(() {
            _selectedRegion = region;
            _regionController.text = region ?? '';
          });
        },
        onSave: (Map<String, dynamic> newProfile) async {
          final provider =
              Provider.of<SellerPanelProvider>(context, listen: false);
          final shop = provider.selectedShop;
          if (shop != null) {
            final ref = FirebaseFirestore.instance
                .collection('shops')
                .doc(shop.id)
                .collection('seller_info')
                .doc('info');
            await ref.set(newProfile, SetOptions(merge: true));
            if (mounted) setState(() => _sellerInfo = newProfile);
          }
        },
        onDelete: _sellerInfo != null
            ? () async {
                // Show loading indicator while checking for products
                showDialog(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF00A36C)),
                    ),
                  ),
                );

                // Check if shop has any listed products
                final hasProducts = await _shopHasListedProducts();

                // Dismiss loading indicator
                if (mounted && Navigator.of(ctx).canPop()) {
                  Navigator.of(ctx).pop();
                }

                // If shop has products, show error dialog and prevent deletion
                if (hasProducts) {
                  if (mounted) {
                    showCupertinoDialog(
                      context: ctx,
                      builder: (context) => CupertinoAlertDialog(
                        title: Text(
                          l10n.cannotDeleteSellerInfo ?? 'Cannot Delete',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Figtree',
                          ),
                        ),
                        content: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.cannotDeleteSellerInfoWithProducts ??
                                'You cannot delete your seller information while you have listed products. Please delete all your products first.',
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              height: 1.4,
                            ),
                          ),
                        ),
                        actions: [
                          CupertinoDialogAction(
                            child: Text(
                              l10n.done ?? 'OK',
                              style: TextStyle(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    );
                  }
                  return;
                }

                // No products found - proceed with deletion confirmation
                final confirm = await showCupertinoDialog<bool>(
                  context: ctx,
                  builder: (context) => CupertinoAlertDialog(
                    title: Text(l10n.delete),
                    content: Text(l10n.deleteSellerInfoConfirmation ??
                        'Are you sure you want to delete your seller information?'),
                    actions: [
                      CupertinoDialogAction(
                        child: Text(l10n.cancel),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        child: Text(l10n.delete),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _deleteSellerInfo();
                  Navigator.of(ctx).pop();
                }
              }
            : null,
      ),
    );
  }

  Widget _buildSellerInfoCard() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: _sellerInfo == null
          ? _buildEmptySellerInfo(l10n, isDark)
          : _buildFilledSellerInfo(l10n, isDark),
    );
  }

  Widget _buildEmptySellerInfo(AppLocalizations l10n, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00A86B).withOpacity(0.1),
                  const Color(0xFF00D4AA).withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.asset(
              'assets/images/payment1.png',
              width: 60,
              height: 60,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noSellerInfo,
            style: GoogleFonts.figtree(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.createSellerProfile,
            style: GoogleFonts.figtree(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showSellerInfoModal(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                l10n.create,
                style: GoogleFonts.figtree(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledSellerInfo(AppLocalizations l10n, bool isDark) {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final isViewer = _isCurrentUserViewer(provider.selectedShop);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.sellerInfo,
                style: GoogleFonts.figtree(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF2D3748),
                ),
              ),
              if (!isViewer)
                IconButton(
                  onPressed: () => _showSellerInfoModal(context),
                  icon: Icon(
                    Icons.edit,
                    size: 20,
                    color: const Color(0xFF00A86B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.phone, l10n.phoneNumber,
              _sellerInfo!['phone'] ?? '', isDark),
          _buildInfoRow(Icons.location_on, l10n.region,
              _sellerInfo!['region'] ?? '', isDark),
          _buildInfoRow(Icons.home, l10n.addressDetails,
              _sellerInfo!['address'] ?? '', isDark),
          _buildInfoRow(
              Icons.person,
              l10n.ibanOwner,
              '${_sellerInfo!['ibanOwnerName'] ?? ''} ${_sellerInfo!['ibanOwnerSurname'] ?? ''}',
              isDark),
          _buildInfoRow(Icons.account_balance, l10n.bankAccountNumberIban,
              _sellerInfo!['iban'] ?? '', isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00A86B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: const Color(0xFF00A86B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.figtree(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '-' : value,
                  style: GoogleFonts.figtree(
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF2D3748),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopCard() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Selector<SellerPanelProvider, DocumentSnapshot?>(
      selector: (_, provider) => provider.selectedShop,
      builder: (context, selectedShop, child) {
        final shopData = selectedShop?.data() as Map<String, dynamic>?;

        if (shopData == null) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                l10n.noShopSelected,
                style: GoogleFonts.figtree(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () {
            context.push('/shop_detail/${selectedShop!.id}');
          },
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: shopData['profileImageUrl']?.isNotEmpty ?? false
                          ? null
                          : LinearGradient(
                              colors: [
                                const Color(0xFF00A86B).withOpacity(0.1),
                                const Color(0xFF00D4AA).withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    ),
                    child: shopData['profileImageUrl']?.isNotEmpty ?? false
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              shopData['profileImageUrl'],
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            Icons.store,
                            color: const Color(0xFF00A86B),
                            size: 30,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopData['name'] ?? l10n.noShopSelected,
                          style: GoogleFonts.figtree(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                isDark ? Colors.white : const Color(0xFF2D3748),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.viewShopDetail,
                          style: GoogleFonts.figtree(
                            fontSize: 12,
                            color: const Color(0xFF00A86B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Optimized Campaign Banner with ValueNotifier
  Widget _buildCampaignBanner() {
    return Consumer<SellerPanelProvider>(
      builder: (context, provider, child) {
        if (!provider.shouldShowCampaignBanner) return const SizedBox.shrink();

        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final bool isViewer = _isCurrentUserViewer(provider.selectedShop);

        return ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: ValueNotifier(provider.activeCampaigns),
          builder: (context, allCampaigns, _) {
            // Safety check
            if (allCampaigns.isEmpty) return const SizedBox.shrink();

            // For viewers, only show campaigns where shop has participated (green banners)
            final campaigns = isViewer
                ? allCampaigns.where((campaign) {
                    final campaignId = campaign['id'] as String? ?? '';
                    return provider.campaignParticipationStatus[campaignId] ??
                        false;
                  }).toList()
                : allCampaigns;

            // If no campaigns to show after filtering, hide banner
            if (campaigns.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              height: 150,
              child: Stack(
                children: [
                  // Scrollable campaign cards
                  PageView.builder(
                    itemCount: campaigns.length,
                    controller: PageController(
                      initialPage: provider.currentCampaignIndex
                          .clamp(0, campaigns.length - 1),
                    ),
                    onPageChanged: (index) {
                      // Safety check before updating index
                      if (index >= 0 && index < campaigns.length) {
                        provider.updateCampaignIndex(index);
                      }
                    },
                    itemBuilder: (context, index) {
                      // Safety check for index bounds
                      if (index >= campaigns.length)
                        return const SizedBox.shrink();

                      final campaign = campaigns[index];
                      final campaignId = campaign['id'] as String? ?? '';
                      final hasParticipated =
                          provider.campaignParticipationStatus[campaignId] ??
                              false;

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: hasParticipated
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasParticipated
                                ? Colors.green.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    hasParticipated
                                        ? 'Kampanyaya Katıldınız! 🎉'
                                        : (campaign['name'] as String? ??
                                            'Kampanya'),
                                    style: GoogleFonts.figtree(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    try {
                                      provider.dismissCampaign();
                                    } catch (e) {
                                      debugPrint(
                                          'Error dismissing campaign: $e');
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Text(
                                hasParticipated
                                    ? (campaign['name'] as String? ??
                                        'Kampanya adı')
                                    : (campaign['description'] as String? ??
                                        'Kampanya açıklaması'),
                                style: GoogleFonts.figtree(
                                  fontSize: 14,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: () {
                                  try {
                                    if (hasParticipated) {
                                      // Navigate to edit campaign screen
                                      context.push(
                                          '/seller_panel_edit_campaign_screen',
                                          extra: {
                                            'campaign': campaign,
                                            'shopId': provider.selectedShop?.id,
                                          });
                                    } else {
                                      // Navigate to create campaign screen
                                      context.push(
                                        '/seller_panel_campaign_screen',
                                        extra: campaign,
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint(
                                        'Error navigating to campaign screen: $e');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasParticipated
                                      ? Colors.green
                                      : Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  hasParticipated ? 'Düzenle' : 'Devam Et',
                                  style: GoogleFonts.figtree(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Campaign counter - bottom left
                  if (campaigns.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${(provider.currentCampaignIndex + 1).clamp(1, campaigns.length)}/${campaigns.length}',
                          style: GoogleFonts.figtree(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  // Page indicators - bottom center
                  if (campaigns.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: campaigns.asMap().entries.map((entry) {
                          final isActive =
                              entry.key == provider.currentCampaignIndex;
                          final campaignId = entry.value['id'] as String? ?? '';
                          final hasParticipated = provider
                                  .campaignParticipationStatus[campaignId] ??
                              false;

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: isActive ? 12 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? (hasParticipated
                                      ? Colors.green
                                      : Colors.orange)
                                  : Colors.grey.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Optimized Metrics Grid with Selector
  Widget _buildMetricsGrid() {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    // Detect tablet - show all boxes in single row with compact sizing
    final isTablet = screenWidth >= 600;
    final crossAxisCount = isTablet ? 6 : 2;
    // Tablet: higher aspect ratio for more compact cards
    final childAspectRatio = isTablet ? 1.1 : 1.4;
    // Tablet: reduced spacing
    final double mainAxisSpacing = isTablet ? 8.0 : 12.0;
    final double crossAxisSpacing = isTablet ? 6.0 : 12.0;

    return Selector<SellerPanelProvider, Map<String, int>?>(
      selector: (_, provider) => provider.cachedMetrics,
      builder: (context, cachedMetrics, child) {
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio: childAspectRatio,
          children: [
            _buildModernMetricCard(
              l10n.productViews,
              Icons.visibility_outlined,
              cachedMetrics?['productViews'] ?? 0,
              [const Color(0xFF667EEA), const Color(0xFF764BA2)],
              isTablet: isTablet,
            ),
            _buildModernMetricCard(
              l10n.soldProducts,
              Icons.trending_up,
              cachedMetrics?['soldProducts'] ?? 0,
              [const Color(0xFF11998E), const Color(0xFF38EF7D)],
              isTablet: isTablet,
            ),
            _buildModernMetricCard(
              l10n.carts,
              Icons.shopping_cart_outlined,
              cachedMetrics?['carts'] ?? 0,
              [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)],
              isTablet: isTablet,
            ),
            _buildModernMetricCard(
              l10n.favorites,
              Icons.favorite_outline,
              cachedMetrics?['favorites'] ?? 0,
              [const Color(0xFFFF6B6B), const Color(0xFFFFE66D)],
              isTablet: isTablet,
            ),
            _buildModernMetricCard(
              l10n.shopViews,
              Icons.storefront_outlined,
              cachedMetrics?['shopViews'] ?? 0,
              [const Color(0xFF06BEB6), const Color(0xFF48B1BF)],
              isTablet: isTablet,
            ),
            _buildModernMetricCard(
              l10n.boosts,
              Icons.rocket_launch_outlined,
              cachedMetrics?['boosts'] ?? 0,
              [const Color(0xFFFF8008), const Color(0xFFFFC837)],
              isTablet: isTablet,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<SellerPanelProvider>(
      builder: (context, provider, child) {
        final currentShopId = provider.selectedShop?.id;

        // Create new future when shop changes
        if (currentShopId != _currentShopId) {
          _initialLoadFuture = _loadDataIfNeeded(currentShopId);
        }

        return FutureBuilder<void>(
          future: _initialLoadFuture,
          key: ValueKey(provider
              .selectedShop?.id), // This key forces rebuild when shop changes
          builder: (context, snapshot) {
            // SHIMMER LOADING STATE
            if (snapshot.connectionState == ConnectionState.waiting) {
              final baseColor = isDark
                  ? const Color.fromARGB(255, 40, 37, 58)
                  : Colors.grey.shade300;
              final highlightColor = isDark
                  ? const Color.fromARGB(255, 60, 57, 78)
                  : Colors.grey.shade100;

              return Shimmer.fromColors(
                baseColor: baseColor,
                highlightColor: highlightColor,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: 6,
                        itemBuilder: (context, index) => _buildShimmerCard(),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        height: 100,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // LOADED STATE
            // Detect tablet for layout adjustments
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final isTablet = screenWidth >= 600;

            // Handle pending seller info modal request (from ProductsTab)
            if (provider.pendingShowSellerInfoModal) {
              provider.clearPendingSellerInfoModal();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _showSellerInfoModal(context);
                }
              });
            }

            return RefreshIndicator(
              onRefresh: () async {
                final provider =
                    Provider.of<SellerPanelProvider>(context, listen: false);
                await provider.fetchShops();
                if (provider.selectedShop != null) {
                  await provider.fetchProducts(
                      shopId: provider.selectedShop!.id);
                  await provider.getMetrics(forceRefresh: true);
                }
                await _fetchSellerInfoIfNeeded();
              },
              child: Container(
                // Ensure gradient fills entire screen on tablets
                constraints:
                    isTablet ? BoxConstraints(minHeight: screenHeight) : null,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            const Color(0xFF0F0F23),
                            const Color(0xFF1A1A2E),
                          ]
                        : [
                            const Color(0xFFF7FAFC),
                            const Color(0xFFEDF2F7),
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    // Tablet: slightly reduced padding for compact layout
                    padding: EdgeInsets.all(isTablet ? 16.0 : 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Campaign Banner - Optimized with ValueNotifier
                        _buildCampaignBanner(),

                        _buildPendingAdPaymentBanners(),

                        // Metrics Grid - Optimized with Selector
                        _buildMetricsGrid(),
                        SizedBox(height: isTablet ? 20.0 : 24.0),

                        // Seller Info Card
                        _buildSellerInfoCard(),
                        SizedBox(height: isTablet ? 12.0 : 16.0),

                        // Shop Card - Optimized with Selector
                        _buildShopCard(),

                        // Extra bottom spacing on tablets to ensure gradient extends
                        if (isTablet) const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class SellerInfoFormModal extends StatefulWidget {
  final Map<String, dynamic>? sellerInfo;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController ibanOwnerNameController;
  final TextEditingController ibanOwnerSurnameController;
  final TextEditingController ibanController;
  final TextEditingController regionController;
  final String? selectedRegion;
  final Function(String?) onRegionSelected;
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback? onDelete;

  const SellerInfoFormModal({
    Key? key,
    this.sellerInfo,
    required this.phoneController,
    required this.addressController,
    required this.ibanOwnerNameController,
    required this.ibanOwnerSurnameController,
    required this.ibanController,
    required this.regionController,
    this.selectedRegion,
    required this.onRegionSelected,
    required this.onSave,
    this.onDelete,
  }) : super(key: key);

  @override
  _SellerInfoFormModalState createState() => _SellerInfoFormModalState();
}

class _SellerInfoFormModalState extends State<SellerInfoFormModal> {
  late String? _selectedRegion;

  @override
  void initState() {
    super.initState();
    _selectedRegion = widget.selectedRegion;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    final borderColor = Colors.grey[400]!;
    final placeholderStyle = TextStyle(
      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85 -
                    MediaQuery.of(context).viewInsets.bottom,
                maxWidth: isTablet ? 500 : double.infinity,
              ),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title with delete button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDarkMode
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.sellerInfo != null
                              ? l10n.editSellerInfo
                              : l10n.createSellerProfile,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Figtree',
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        if (widget.onDelete != null)
                          GestureDetector(
                            onTap: widget.onDelete,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Content area - scrollable form fields
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Phone Number
                          _buildTextField(
                            controller: widget.phoneController,
                            placeholder: '(5__) ___ __ __',
                            keyboardType: TextInputType.phone,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            inputFormatters: [_PhoneNumberFormatter()],
                          ),
                          const SizedBox(height: 12),

                          // Region Selector
                          GestureDetector(
                            onTap: () => _showRegionPicker(context),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: borderColor, width: 1),
                                borderRadius: BorderRadius.circular(8),
                                color: isDarkMode
                                    ? const Color.fromARGB(255, 45, 43, 61)
                                    : Colors.grey.shade50,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _selectedRegion ?? l10n.region,
                                    style: TextStyle(
                                      color: _selectedRegion != null
                                          ? (isDarkMode
                                              ? Colors.white
                                              : Colors.black)
                                          : (isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[600]),
                                      fontSize: 16,
                                    ),
                                  ),
                                  Icon(
                                    CupertinoIcons.chevron_down,
                                    color: isDarkMode
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Address
                          _buildTextField(
                            controller: widget.addressController,
                            placeholder: l10n.addressDetails,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                          ),
                          const SizedBox(height: 12),

                          // IBAN Owner Name
                          _buildTextField(
                            controller: widget.ibanOwnerNameController,
                            placeholder: l10n.ibanOwnerName,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                          ),
                          const SizedBox(height: 12),

                          // IBAN Owner Surname
                          _buildTextField(
                            controller: widget.ibanOwnerSurnameController,
                            placeholder: l10n.ibanOwnerSurname,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                          ),
                          const SizedBox(height: 12),

                          // IBAN
                          _buildTextField(
                            controller: widget.ibanController,
                            placeholder: 'TR__ ____ ____ ____ ____ ____ __',
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            inputFormatters: [_TurkishIbanFormatter()],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom buttons
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDarkMode
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                l10n.cancel,
                                style: TextStyle(
                                  fontFamily: 'Figtree',
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CupertinoButton(
                              color: (widget.phoneController.text.isEmpty ||
                                      _selectedRegion == null)
                                  ? CupertinoColors.inactiveGray
                                  : const Color(0xFF00A36C),
                              onPressed: (widget.phoneController.text.isEmpty ||
                                      _selectedRegion == null)
                                  ? null
                                  : () {
                                      final l10n = AppLocalizations.of(context);

                                      // Validate phone: must be 10 digits
                                      final phoneDigits = widget
                                          .phoneController.text
                                          .replaceAll(RegExp(r'\D'), '');
                                      if (phoneDigits.length != 10) {
                                        showCupertinoDialog(
                                          context: context,
                                          builder: (context) =>
                                              CupertinoAlertDialog(
                                            title: Text(l10n.error),
                                            content:
                                                Text(l10n.invalidPhoneNumber),
                                            actions: [
                                              CupertinoDialogAction(
                                                child: Text(l10n.done),
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                              ),
                                            ],
                                          ),
                                        );
                                        return;
                                      }

                                      // Validate IBAN if provided
                                      final ibanText =
                                          widget.ibanController.text.trim();
                                      if (ibanText.isNotEmpty) {
                                        final normalizedIban = ibanText
                                            .replaceAll(' ', '')
                                            .toUpperCase();
                                        if (normalizedIban.length != 26 ||
                                            !normalizedIban.startsWith('TR')) {
                                          showCupertinoDialog(
                                            context: context,
                                            builder: (context) =>
                                                CupertinoAlertDialog(
                                              title: Text(l10n.error),
                                              content: Text(l10n.invalidIban ??
                                                  'Invalid IBAN. Turkish IBAN must be TR followed by 24 digits.'),
                                              actions: [
                                                CupertinoDialogAction(
                                                  child: Text(l10n.done),
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                ),
                                              ],
                                            ),
                                          );
                                          return;
                                        }
                                      }

                                      // Normalize phone and IBAN for storage
                                      final normalizedPhone = '0$phoneDigits';
                                      final normalizedIban = ibanText.isNotEmpty
                                          ? ibanText
                                              .replaceAll(' ', '')
                                              .toUpperCase()
                                          : '';

                                      final newProfile = {
                                        'phone': normalizedPhone,
                                        'region': _selectedRegion ?? '',
                                        'address': widget.addressController.text
                                            .trim(),
                                        'ibanOwnerName': widget
                                            .ibanOwnerNameController.text
                                            .trim(),
                                        'ibanOwnerSurname': widget
                                            .ibanOwnerSurnameController.text
                                            .trim(),
                                        'iban': normalizedIban,
                                      };
                                      Navigator.pop(context);
                                      widget.onSave(newProfile);
                                    },
                              child: Text(
                                widget.sellerInfo != null
                                    ? l10n.save
                                    : l10n.create,
                                style: const TextStyle(
                                  fontFamily: 'Figtree',
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to build text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    required bool isDark,
    required Color borderColor,
    required TextStyle placeholderStyle,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      maxLines: maxLines,
      padding: const EdgeInsets.all(12),
      inputFormatters: inputFormatters,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 16,
      ),
      placeholderStyle: placeholderStyle,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(8),
        color: isDark
            ? const Color.fromARGB(255, 45, 43, 61)
            : Colors.grey.shade50,
      ),
      cursorColor: isDark ? Colors.white : Colors.black,
    );
  }

  Future<void> _showRegionPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    // Step 1: Show main regions
    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text(
          l10n.selectMainRegion ?? 'Select Main Region',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
            fontFamily: 'Figtree',
            fontSize: 16,
          ),
        ),
        actions: mainRegions.map((mainRegion) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showSubregionPicker(context, mainRegion);
            },
            child: Text(
              mainRegion,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
                fontSize: 16,
              ),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Figtree',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSubregionPicker(
      BuildContext context, String selectedMainRegion) async {
    final l10n = AppLocalizations.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final subregions = regionHierarchy[selectedMainRegion] ?? [];

    // Step 2: Show subregions for the selected main region
    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Column(
          children: [
            Text(
              selectedMainRegion,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'Figtree',
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.selectSubregion ?? 'Select Subregion',
              style: TextStyle(
                color: isLight ? Colors.black54 : Colors.white70,
                fontWeight: FontWeight.w500,
                fontFamily: 'Figtree',
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          // Option to select the main region itself
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedRegion = selectedMainRegion;
                widget.regionController.text = selectedMainRegion;
              });
              widget.onRegionSelected(selectedMainRegion);
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_city_rounded,
                  color: const Color(0xFF00A86B),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '$selectedMainRegion (${l10n.mainRegion ?? 'Main Region'})',
                  style: TextStyle(
                    color: const Color(0xFF00A86B),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Figtree',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          if (subregions.isNotEmpty)
            Container(
              height: 1,
              color: isLight ? Colors.black12 : Colors.white24,
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),
          // Subregions
          ...subregions.map((subregion) {
            return CupertinoActionSheetAction(
              onPressed: () {
                setState(() {
                  _selectedRegion = subregion;
                  widget.regionController.text = subregion;
                });
                widget.onRegionSelected(subregion);
                Navigator.pop(context);
              },
              child: Text(
                subregion,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                  fontSize: 16,
                ),
              ),
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            // Go back to main region selection
            _showRegionPicker(context);
          },
          child: Text(
            '← ${l10n.back ?? 'Back'}',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Figtree',
            ),
          ),
        ),
      ),
    );
  }
}

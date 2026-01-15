import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../PAYMENT-RECEIPT/dynamic_payment_screen.dart';
import 'dart:io';
import '../../generated/l10n/app_localizations.dart';
import '../../utils/image_compression_utils.dart';
import '../../models/product.dart';
import 'ad_analytics_screen.dart';
import 'dart:async';

enum AdType { topBanner, thinBanner, marketBanner }

enum AdStatus { pending, approved, rejected, paid, active }

enum AdDuration { oneWeek, twoWeeks, oneMonth }

class AdSubmission {
  final String id;
  final String userId;
  final String shopId;
  final String shopName; // ✅ ADD THIS LINE
  final AdType adType;
  final String imageUrl;
  final AdStatus status;
  final AdDuration duration;
  final String? rejectionReason;
  final String? paymentLink;
  final double? price;
  final Timestamp createdAt;
  final Timestamp? reviewedAt;
  final Timestamp? paidAt;
  final String? linkType; // 'shop' or 'product'
  final String? linkedShopId;
  final String? linkedProductId;
  final String? activeAdId;
  final Timestamp? expiresAt;
  final Timestamp? expiredAt;

  AdSubmission({
    required this.id,
    required this.userId,
    required this.shopId,
    required this.shopName, // ✅ ADD THIS LINE
    required this.adType,
    required this.imageUrl,
    required this.status,
    required this.duration,
    this.rejectionReason,
    this.paymentLink,
    this.price,
    required this.createdAt,
    this.reviewedAt,
    this.paidAt,
    this.linkType,
    this.linkedShopId,
    this.linkedProductId,
    this.activeAdId,
    this.expiresAt,
    this.expiredAt,
  });

  factory AdSubmission.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdSubmission(
      id: doc.id,
      userId: data['userId'] ?? '',
      shopId: data['shopId'] ?? '',
      shopName: data['shopName'] ?? '', // ✅ ADD THIS LINE
      adType: _adTypeFromString(data['adType'] ?? 'marketBanner'),
      imageUrl: data['imageUrl'] ?? '',
      status: _statusFromString(data['status'] ?? 'pending'),
      duration: _durationFromString(data['duration'] ?? 'oneWeek'),
      rejectionReason: data['rejectionReason'],
      paymentLink: data['paymentLink'],
      price: data['price']?.toDouble(),
      createdAt: data['createdAt'] ?? Timestamp.now(),
      reviewedAt: data['reviewedAt'],
      paidAt: data['paidAt'],
      linkType: data['linkType'],
      linkedShopId: data['linkedShopId'],
      linkedProductId: data['linkedProductId'],
      activeAdId: data['activeAdId'],
      expiresAt: data['expiresAt'],
      expiredAt: data['expiredAt'],
    );
  }

  static AdType _adTypeFromString(String type) {
    switch (type) {
      case 'topBanner':
        return AdType.topBanner;
      case 'thinBanner':
        return AdType.thinBanner;
      case 'marketBanner':
        return AdType.marketBanner;
      default:
        return AdType.marketBanner;
    }
  }

  static AdStatus _statusFromString(String status) {
    switch (status) {
      case 'pending':
        return AdStatus.pending;
      case 'approved':
        return AdStatus.approved;
      case 'rejected':
        return AdStatus.rejected;
      case 'paid':
        return AdStatus.paid;
      case 'active':
        return AdStatus.active;
      default:
        return AdStatus.pending;
    }
  }

  static AdDuration _durationFromString(String duration) {
    switch (duration) {
      case 'oneWeek':
        return AdDuration.oneWeek;
      case 'twoWeeks':
        return AdDuration.twoWeeks;
      case 'oneMonth':
        return AdDuration.oneMonth;
      default:
        return AdDuration.oneWeek;
    }
  }
}

/// Service class to manage ad prices with caching
class AdPricesService {
  static final AdPricesService _instance = AdPricesService._internal();
  factory AdPricesService() => _instance;
  AdPricesService._internal();
  bool _serviceEnabled = true;
bool get serviceEnabled => _serviceEnabled;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Map<AdType, Map<AdDuration, double>>? _cachedPrices;
  StreamSubscription<DocumentSnapshot>? _subscription;
  final _pricesController = StreamController<Map<AdType, Map<AdDuration, double>>>.broadcast();

  Stream<Map<AdType, Map<AdDuration, double>>> get pricesStream => _pricesController.stream;

  Map<AdType, Map<AdDuration, double>> get defaultPrices => {
    AdType.topBanner: {
      AdDuration.oneWeek: 4000.0,
      AdDuration.twoWeeks: 7500.0,
      AdDuration.oneMonth: 14000.0,
    },
    AdType.thinBanner: {
      AdDuration.oneWeek: 2000.0,
      AdDuration.twoWeeks: 3500.0,
      AdDuration.oneMonth: 6500.0,
    },
    AdType.marketBanner: {
      AdDuration.oneWeek: 2500.0,
      AdDuration.twoWeeks: 4500.0,
      AdDuration.oneMonth: 8500.0,
    },
  };

  void startListening() {
    if (_subscription != null) return;

  _subscription = _firestore
    .collection('app_config')
    .doc('ad_prices')
    .snapshots()
    .listen((snapshot) {
  if (snapshot.exists) {
    final data = snapshot.data() as Map<String, dynamic>;
    _serviceEnabled = data['serviceEnabled'] ?? true;  // Add this line
    _cachedPrices = _parsePrices(data);
    _pricesController.add(_cachedPrices!);
  } else {
    _serviceEnabled = true;  // Add this line
    _cachedPrices = defaultPrices;
    _pricesController.add(_cachedPrices!);
  }
}, onError: (e) {
  debugPrint('Error listening to ad prices: $e');
  _serviceEnabled = true;  // Add this line
  _cachedPrices ??= defaultPrices;
  _pricesController.add(_cachedPrices!);
});
  }

  Map<AdType, Map<AdDuration, double>> _parsePrices(Map<String, dynamic> data) {
    _serviceEnabled = data['serviceEnabled'] ?? true;
    return {
      AdType.topBanner: {
        AdDuration.oneWeek: (data['topBanner']?['oneWeek'] ?? 4000).toDouble(),
        AdDuration.twoWeeks: (data['topBanner']?['twoWeeks'] ?? 7500).toDouble(),
        AdDuration.oneMonth: (data['topBanner']?['oneMonth'] ?? 14000).toDouble(),
      },
      AdType.thinBanner: {
        AdDuration.oneWeek: (data['thinBanner']?['oneWeek'] ?? 2000).toDouble(),
        AdDuration.twoWeeks: (data['thinBanner']?['twoWeeks'] ?? 3500).toDouble(),
        AdDuration.oneMonth: (data['thinBanner']?['oneMonth'] ?? 6500).toDouble(),
      },
      AdType.marketBanner: {
        AdDuration.oneWeek: (data['marketBanner']?['oneWeek'] ?? 2500).toDouble(),
        AdDuration.twoWeeks: (data['marketBanner']?['twoWeeks'] ?? 4500).toDouble(),
        AdDuration.oneMonth: (data['marketBanner']?['oneMonth'] ?? 8500).toDouble(),
      },
    };
  }

  double getPrice(AdType adType, AdDuration duration) {
    return _cachedPrices?[adType]?[duration] ?? defaultPrices[adType]![duration]!;
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}

class AdsScreen extends StatefulWidget {
  final String shopId;
  final String shopName;

  const AdsScreen({
    super.key,
    required this.shopId,
    required this.shopName,
  });

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  final AdPricesService _pricesService = AdPricesService();
  StreamSubscription<Map<AdType, Map<AdDuration, double>>>? _pricesSubscription;

  TabController? _tabController;
  List<AdSubmission> _submissions = [];
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isViewer = false;


  bool _isCheckingRole = true;

  // State for ad type selection
  AdType? _selectedAdType;
  AdDuration _selectedDuration = AdDuration.oneWeek;

 @override
  void initState() {
    super.initState();
    _pricesService.startListening();
    _pricesSubscription = _pricesService.pricesStream.listen((_) {
      if (mounted) setState(() {});
    });
    _checkUserRole();
    _loadSubmissions();
  }

  Future<void> _checkUserRole() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) {
        setState(() => _isCheckingRole = false);
        _initTabController();
        return;
      }

      final shopDoc = await _firestore.collection('shops').doc(widget.shopId).get();
      if (shopDoc.exists) {
        final shopData = shopDoc.data() as Map<String, dynamic>?;
        if (shopData != null) {
          final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
          _isViewer = viewers.contains(currentUserId);
        }
      }
    } catch (e) {
      debugPrint('Error checking user role: $e');
    } finally {
      setState(() => _isCheckingRole = false);
      _initTabController();
    }
  }

  void _initTabController() {
    // Viewers only see "My Ads" tab (1 tab), others see both tabs
    _tabController = TabController(
      length: _isViewer ? 1 : 2,
      vsync: this,
    );
  }

 @override
  void dispose() {
    _tabController?.dispose();
    _pricesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSubmissions() async {
    setState(() => _isLoading = true);

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final snapshot = await _firestore
          .collection('ad_submissions')
          .where('shopId', isEqualTo: widget.shopId)
          .orderBy('createdAt', descending: true)
          .get();

      _submissions =
          snapshot.docs.map((doc) => AdSubmission.fromDocument(doc)).toList();
    } catch (e) {
      debugPrint('Error loading submissions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  double _getPrice(AdType adType, AdDuration duration) {
    return _pricesService.getPrice(adType, duration);
  }

 

  void _showDurationSelectionSheet(AdType adType) {
    final l10n = AppLocalizations.of(context);
    setState(() => _selectedAdType = adType);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1B23) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getAdTypeColor(adType).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getAdTypeIcon(adType),
                        color: _getAdTypeColor(adType),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.selectDuration,
                        style: GoogleFonts.figtree(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A202C),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Duration Options
                _buildDurationOption(
                  l10n,
                  isDark,
                  AdDuration.oneWeek,
                  l10n.oneWeek,
                  _getPrice(adType, AdDuration.oneWeek),
                  setModalState,
                ),
                const SizedBox(height: 12),
                _buildDurationOption(
                  l10n,
                  isDark,
                  AdDuration.twoWeeks,
                  l10n.twoWeeks,
                  _getPrice(adType, AdDuration.twoWeeks),
                  setModalState,
                ),
                const SizedBox(height: 12),
                _buildDurationOption(
                  l10n,
                  isDark,
                  AdDuration.oneMonth,
                  l10n.oneMonth,
                  _getPrice(adType, AdDuration.oneMonth),
                  setModalState,
                  isRecommended: true,
                ),
                const SizedBox(height: 24),

                // Confirm Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _pickAndUploadImage(adType, _selectedDuration);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getAdTypeColor(adType),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      '${l10n.continueText} • ${_getPrice(adType, _selectedDuration).toStringAsFixed(0)} TL',
                      style: GoogleFonts.figtree(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDurationOption(
    AppLocalizations l10n,
    bool isDark,
    AdDuration duration,
    String label,
    double price,
    StateSetter setModalState, {
    bool isRecommended = false,
  }) {
    final isSelected = _selectedDuration == duration;

    return GestureDetector(
      onTap: () {
        setModalState(() => _selectedDuration = duration);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected
              ? null
              : isDark
                  ? const Color(0xFF2D3748)
                  : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : isDark
                    ? const Color(0xFF4A5568)
                    : const Color(0xFFE2E8F0),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.white : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? Colors.white
                      : isDark
                          ? const Color(0xFF718096)
                          : const Color(0xFF94A3B8),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Color(0xFF667EEA),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.figtree(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : isDark
                                  ? Colors.white
                                  : const Color(0xFF1A202C),
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withOpacity(0.2)
                                : const Color(0xFF38A169).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.recommended,
                            style: GoogleFonts.figtree(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF38A169),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${price.toStringAsFixed(0)} TL',
                    style: GoogleFonts.figtree(
                      fontSize: 14,
                      color: isSelected
                          ? Colors.white.withOpacity(0.9)
                          : isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (duration == AdDuration.oneMonth) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.2)
                      : const Color(0xFF38A169).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.bestValue,
                  style: GoogleFonts.figtree(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF38A169),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage(AdType adType, AdDuration duration) async {
    final l10n = AppLocalizations.of(context);

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (image == null) return;

    // ✅ ADD VALIDATION HERE (before showing modal)
    final originalFile = File(image.path);

    // Validate file size
    final fileSize = await originalFile.length();
    if (fileSize > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.imageTooLarge,
                  style: GoogleFonts.figtree(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFE53E3E),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Validate file format
    final fileName = image.path.toLowerCase();
    final validFormats = ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'];
    final hasValidFormat = validFormats.any((ext) => fileName.endsWith(ext));

    if (!hasValidFormat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Only JPG, PNG, WebP, and HEIC formats are allowed',
                  style: GoogleFonts.figtree(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFE53E3E),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    String? linkType;
    String? linkedShopId;
    String? linkedProductId;
    bool linkSelectionCompleted = false; // ✅ ADD THIS FLAG

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdLinkSelectionSheet(
        shopId: widget.shopId,
        shopName: widget.shopName,
        onLinkSelected: (type, shopId, productId) {
          linkType = type;
          linkedShopId = shopId;
          linkedProductId = productId;
          linkSelectionCompleted = true; // ✅ SET FLAG TO TRUE
        },
      ),
    );

    // ✅ CHECK IF USER COMPLETED LINK SELECTION
    if (!linkSelectionCompleted) {
      // User closed the modal without selecting anything
      debugPrint('⚠️ Link selection cancelled by user');
      return; // Exit the function
    }

    // Create a GlobalKey to access the modal's state
    final modalKey = GlobalKey<_UploadProgressModalState>();

    // Show upload modal
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx; // ← Save the dialog's context
        return UploadProgressModal(
          key: modalKey,
          shopName: widget.shopName,
          adType: adType,
        );
      },
    );

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      // STAGE 1: Compress Image (0% - 30%)
      modalKey.currentState?.updateProgress(0.1, l10n.preparingImage);

      final compressedFile =
          await ImageCompressionUtils.ecommerceCompress(originalFile);

      if (compressedFile == null) {
        throw Exception('Image compression failed');
      }

      // Log compression results
      final originalSize = await originalFile.length();
      final compressedSize = await compressedFile.length();
      debugPrint(
          '✅ Compression: ${(originalSize / 1024 / 1024).toStringAsFixed(2)} MB → ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // STAGE 2: Upload to Storage (30% - 80%)
      modalKey.currentState?.updateProgress(0.3, l10n.uploadingImage);

      final fileName =
          'ad_submissions/${widget.shopId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(fileName);

      await ref.putFile(compressedFile);

      modalKey.currentState?.updateProgress(0.8, l10n.uploadingImage);
      final imageUrl = await ref.getDownloadURL();

      // STAGE 3: Save to Firestore (80% - 100%)
      modalKey.currentState?.updateProgress(0.85, l10n.savingAdData);

      final price = _getPrice(adType, duration);

      await _firestore.collection('ad_submissions').add({
        'userId': userId,
        'shopId': widget.shopId,
        'shopName': widget.shopName,
        'adType': _adTypeToString(adType),
        'duration': _durationToString(duration),
        'price': price,
        'imageUrl': imageUrl,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'linkType': linkType,
        'linkedShopId': linkedShopId,
        'linkedProductId': linkedProductId,
      });

      modalKey.currentState?.updateProgress(1.0, l10n.complete);

      // Clean up temporary file
      try {
        if (await compressedFile.exists()) {
          await compressedFile.delete();
        }
      } catch (e) {
        debugPrint('⚠️ Failed to delete temporary file: $e');
      }

      // Wait a moment to show 100% completion
      await Future.delayed(const Duration(milliseconds: 500));

      // Close modal
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.adSubmittedSuccessfully,
                        style: GoogleFonts.figtree(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.adUnderReview,
                        style: GoogleFonts.figtree(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF38A169),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

        _loadSubmissions();
      }
    } catch (e) {
      debugPrint('❌ Error uploading ad: $e');

      // Close modal
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.toString().contains('too large')
                        ? l10n.imageTooLarge
                        : l10n.errorUploadingAd,
                    style: GoogleFonts.figtree(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFE53E3E),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  String _adTypeToString(AdType type) {
    switch (type) {
      case AdType.topBanner:
        return 'topBanner';
      case AdType.thinBanner:
        return 'thinBanner';
      case AdType.marketBanner:
        return 'marketBanner';
    }
  }

  String _durationToString(AdDuration duration) {
    switch (duration) {
      case AdDuration.oneWeek:
        return 'oneWeek';
      case AdDuration.twoWeeks:
        return 'twoWeeks';
      case AdDuration.oneMonth:
        return 'oneMonth';
    }
  }

  IconData _getAdTypeIcon(AdType type) {
    switch (type) {
      case AdType.topBanner:
        return Icons.view_carousel_rounded;
      case AdType.thinBanner:
        return Icons.view_week_rounded;
      case AdType.marketBanner:
        return Icons.grid_view_rounded;
    }
  }

  Color _getAdTypeColor(AdType type) {
    switch (type) {
      case AdType.topBanner:
        return const Color(0xFF667EEA);
      case AdType.thinBanner:
        return const Color(0xFFED8936);
      case AdType.marketBanner:
        return const Color(0xFF9F7AEA);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading while checking user role
    if (_isCheckingRole || _tabController == null) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
        appBar: _buildAppBar(l10n, isDark),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(l10n, isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildTabBar(l10n, isDark),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _isViewer
                    ? [_buildMyAdsTab(l10n, isDark)]
                    : [
                        _buildCreateAdTab(l10n, isDark),
                        _buildMyAdsTab(l10n, isDark),
                      ],
              ),
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
        l10n.adManagement,
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

  Widget _buildTabBar(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tabs: _isViewer
            ? [Tab(text: l10n.myAds)]
            : [
                Tab(text: l10n.createAd),
                Tab(text: l10n.myAds),
              ],
      ),
    );
  }

  Widget _buildCreateAdTab(AppLocalizations l10n, bool isDark) {
      if (!_pricesService.serviceEnabled) {
    return _buildServiceDisabledState(l10n, isDark);
  }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF667EEA).withOpacity(0.1),
                  const Color(0xFF764BA2).withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF667EEA).withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF667EEA),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.adSubmissionInfo,
                    style: GoogleFonts.figtree(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFFA0AAB8)
                          : const Color(0xFF4A5568),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Ad Types Section
          Text(
            l10n.selectAdType,
            style: GoogleFonts.figtree(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A202C),
            ),
          ),
          const SizedBox(height: 16),

          // Ad Type Cards
          _buildAdTypeCard(
            l10n,
            isDark,
            AdType.topBanner,
            Icons.view_carousel_rounded,
            l10n.topBanner,
            l10n.topBannerDescription,
            l10n.bannerDimensions,
            const Color(0xFF667EEA),
          ),
          const SizedBox(height: 12),
          _buildAdTypeCard(
            l10n,
            isDark,
            AdType.thinBanner,
            Icons.view_week_rounded,
            l10n.thinBanner,
            l10n.thinBannerDescription,
            l10n.bannerDimensions,
            const Color(0xFFED8936),
          ),
          const SizedBox(height: 12),
          _buildAdTypeCard(
            l10n,
            isDark,
            AdType.marketBanner,
            Icons.grid_view_rounded,
            l10n.marketBanner,
            l10n.marketBannerDescription,
            l10n.bannerDimensions,
            const Color(0xFF9F7AEA),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceDisabledState(AppLocalizations l10n, bool isDark) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFED8936).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.pause_circle_outline_rounded,
              size: 64,
              color: Color(0xFFED8936),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.adServiceTemporarilyOff,
            style: GoogleFonts.figtree(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A202C),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.adServiceDisabledMessage,
            style: GoogleFonts.figtree(
              fontSize: 14,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

  Widget _buildAdTypeCard(
    AppLocalizations l10n,
    bool isDark,
    AdType adType,
    IconData icon,
    String title,
    String description,
    String dimensions,
    Color accentColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 37, 35, 54) : null,
        gradient: isDark
            ? null
            : LinearGradient(
                colors: [Colors.white, const Color(0xFFFAFBFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              _isUploading ? null : () => _showDurationSelectionSheet(adType),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: accentColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.figtree(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A202C),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: GoogleFonts.figtree(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.bannerDimensions,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFED8936), // Orange color
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: accentColor.withOpacity(0.5),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPriceItem(
                        l10n.oneWeekShort,
                        _getPrice(adType, AdDuration.oneWeek),
                        isDark,
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: isDark
                            ? const Color(0xFF4A5568)
                            : const Color(0xFFE2E8F0),
                      ),
                      _buildPriceItem(
                        l10n.twoWeeksShort,
                        _getPrice(adType, AdDuration.twoWeeks),
                        isDark,
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: isDark
                            ? const Color(0xFF4A5568)
                            : const Color(0xFFE2E8F0),
                      ),
                      _buildPriceItem(
                        l10n.oneMonthShort,
                        _getPrice(adType, AdDuration.oneMonth),
                        isDark,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceItem(String duration, double price, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(
            duration,
            style: GoogleFonts.figtree(
              fontSize: 11,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${price.toStringAsFixed(0)} TL',
            style: GoogleFonts.figtree(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A202C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyAdsTab(AppLocalizations l10n, bool isDark) {
    if (_isLoading) {
      return _buildLoadingList(isDark);
    }

    if (_submissions.isEmpty) {
      return _buildEmptyState(
        l10n.noAdsYet,
        l10n.submitYourFirstAd,
        isDark,
      );
    }

    // Detect tablet and orientation
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isTabletLandscape = isTablet && isLandscape;

    // On tablets, show 3-4 cards per row in a grid
    if (isTablet) {
      // Use fixed mainAxisExtent for precise height control
      // Tablet landscape: taller cards to prevent overflow
      // Tablet portrait: moderate height
      final double cardHeight = isTabletLandscape ? 280.0 : 320.0;

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isLandscape ? 4 : 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: cardHeight,
        ),
        itemCount: _submissions.length,
        itemBuilder: (context, index) {
          return _buildSubmissionCard(_submissions[index], l10n, isDark,
              isTablet: true, isTabletLandscape: isTabletLandscape);
        },
      );
    }

    // Mobile: single column list
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _submissions.length,
      itemBuilder: (context, index) {
        return _buildSubmissionCard(_submissions[index], l10n, isDark);
      },
    );
  }

  AdStatus _getEffectiveStatus(AdSubmission submission) {
    // If there's a paidAt timestamp, show "paid" label
    if (submission.paidAt != null && submission.status != AdStatus.active) {
      return AdStatus.paid;
    }

    // If status is approved and there's no paidAt, show "approved"
    if (submission.status == AdStatus.approved) {
      return AdStatus.approved;
    }

    // Otherwise return the original status
    return submission.status;
  }

  Widget _buildSubmissionCard(
    AdSubmission submission,
    AppLocalizations l10n,
    bool isDark, {
    bool isTablet = false,
    bool isTabletLandscape = false,
  }) {
    // Scale down text and padding for tablet grid view
    final double titleFontSize = isTablet ? 10.0 : 12.0;
    final double badgeFontSize = isTablet ? 9.0 : 11.0;
    final double iconSize = isTablet ? 12.0 : 14.0;
    final double padding = isTablet ? 10.0 : 16.0;
    final double badgePaddingH = isTablet ? 6.0 : 10.0;
    final double badgePaddingV = isTablet ? 3.0 : 5.0;
    final double borderRadius = isTablet ? 12.0 : 16.0;

    return Container(
      margin: isTablet ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 37, 35, 54) : null,
        gradient: isDark
            ? null
            : LinearGradient(
                colors: [Colors.white, const Color(0xFFFAFBFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: _getStatusColor(submission.status).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image - use Flexible on tablet to allow shrinking if needed
          ClipRRect(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(borderRadius)),
            child: AspectRatio(
              // Tablet landscape: wider aspect ratio for more compact image
              // Tablet portrait: moderate aspect ratio
              aspectRatio: isTabletLandscape ? 2.8 : (isTablet ? 2.2 : _getAspectRatio(submission.adType)),
              child: CachedNetworkImage(
                imageUrl: submission.imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: isDark
                      ? const Color(0xFF2D3748)
                      : const Color(0xFFF7FAFC),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: isDark
                      ? const Color(0xFF2D3748)
                      : const Color(0xFFF7FAFC),
                  child: const Icon(Icons.error_outline_rounded),
                ),
              ),
            ),
          ),

          // Info Section - use Expanded on tablet to fill remaining space and prevent overflow
          if (isTablet)
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildStatusBadge(_getEffectiveStatus(submission), l10n,
                        isTablet: isTablet),
                    _buildAdTypeBadge(submission.adType, l10n, isDark,
                        isTablet: isTablet),
                    // Countdown badge
                    if ((submission.status == AdStatus.active ||
                            submission.status == AdStatus.paid) &&
                        submission.expiresAt != null)
                      _buildCountdownBadge(submission, l10n, isDark,
                          isTablet: isTablet),
                  ],
                ),
                SizedBox(height: isTablet ? 6 : 12),
                // Hide detailed info on tablet to save space
                if (!isTablet) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: iconSize,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getDurationLabel(submission.duration, l10n),
                        style: GoogleFonts.figtree(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.payments_rounded,
                        size: iconSize,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${submission.price?.toStringAsFixed(0) ?? '0'} TL',
                        style: GoogleFonts.figtree(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A202C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  isTablet
                      ? '${submission.price?.toStringAsFixed(0) ?? '0'} TL'
                      : _formatDate(submission.createdAt, l10n),
                  style: GoogleFonts.figtree(
                    fontSize: isTablet ? 11.0 : 11.0,
                    fontWeight: isTablet ? FontWeight.w600 : FontWeight.normal,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),

                // Analytics Button - show on both mobile and tablet (compact on tablet)
                if (submission.activeAdId != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: isTablet
                        // Tablet: Compact icon-only button
                        ? OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdAnalyticsScreen(
                                    adId: submission.activeAdId!,
                                    adType: _adTypeToString(submission.adType),
                                    adName:
                                        '${_getAdTypeLabel(submission.adType, l10n)} - ${widget.shopName}',
                                  ),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF667EEA),
                              side: const BorderSide(
                                color: Color(0xFF667EEA),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.analytics_rounded, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.viewAnalytics ?? 'Analytics',
                                  style: GoogleFonts.figtree(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        // Mobile: Full button with icon and label
                        : OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdAnalyticsScreen(
                                    adId: submission.activeAdId!,
                                    adType: _adTypeToString(submission.adType),
                                    adName:
                                        '${_getAdTypeLabel(submission.adType, l10n)} - ${widget.shopName}',
                                  ),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF667EEA),
                              side: const BorderSide(
                                color: Color(0xFF667EEA),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.analytics_rounded, size: 20),
                            label: Text(
                              l10n.viewAnalytics ?? 'View Analytics',
                              style: GoogleFonts.figtree(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                ],

                // Show approval/rejection messages - compact on tablet, full on mobile
                // ✅ SHOW APPROVAL MESSAGE FOR APPROVED STATUS
                if (submission.status == AdStatus.approved) ...[
                  SizedBox(height: isTablet ? 6 : 12),
                  Container(
                    padding: EdgeInsets.all(isTablet ? 8 : 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38A169).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF38A169).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: const Color(0xFF38A169),
                          size: isTablet ? 14 : 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.adApprovedMessage,
                            style: GoogleFonts.figtree(
                              fontSize: isTablet ? 10 : 12,
                              color: const Color(0xFF38A169),
                            ),
                            maxLines: isTablet ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Rejection Reason - show on both mobile and tablet
                if (submission.status == AdStatus.rejected &&
                    submission.rejectionReason != null) ...[
                  SizedBox(height: isTablet ? 6 : 12),
                  Container(
                    padding: EdgeInsets.all(isTablet ? 8 : 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53E3E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE53E3E).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: const Color(0xFFE53E3E),
                          size: isTablet ? 14 : 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            submission.rejectionReason!,
                            style: GoogleFonts.figtree(
                              fontSize: isTablet ? 10 : 12,
                              color: const Color(0xFFE53E3E),
                            ),
                            maxLines: isTablet ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Payment Button (for approved ads) - hide on tablet to save space and for viewers
                if (!isTablet &&
                    !_isViewer &&
                    submission.status == AdStatus.approved &&
                    submission.paymentLink != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DynamicPaymentScreen(
                              submissionId: submission.id,
                              adType: submission.adType.name,
                              duration: submission.duration.name,
                              price: submission.price!,
                              imageUrl: submission.imageUrl,
                              shopName: submission.shopName,
                              paymentLink: submission.paymentLink!,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38A169),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.payment_rounded, size: 20),
                      label: Text(
                        '${l10n.proceedToPayment} (${submission.price!.toStringAsFixed(0)} TL)',
                        style: GoogleFonts.figtree(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
                  ),
                ),
              ),
            ),
          // Mobile: regular Padding without Expanded
          if (!isTablet)
            Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildStatusBadge(_getEffectiveStatus(submission), l10n,
                          isTablet: isTablet),
                      _buildAdTypeBadge(submission.adType, l10n, isDark,
                          isTablet: isTablet),
                      if ((submission.status == AdStatus.active ||
                              submission.status == AdStatus.paid) &&
                          submission.expiresAt != null)
                        _buildCountdownBadge(submission, l10n, isDark,
                            isTablet: isTablet),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: iconSize,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getDurationLabel(submission.duration, l10n),
                        style: GoogleFonts.figtree(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.payments_rounded,
                        size: iconSize,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${submission.price?.toStringAsFixed(0) ?? '0'} TL',
                        style: GoogleFonts.figtree(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1A202C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(submission.createdAt, l10n),
                    style: GoogleFonts.figtree(
                      fontSize: 11.0,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  // Analytics Button for mobile
                  if (submission.activeAdId != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdAnalyticsScreen(
                                adId: submission.activeAdId!,
                                adType: _adTypeToString(submission.adType),
                                adName:
                                    '${_getAdTypeLabel(submission.adType, l10n)} - ${widget.shopName}',
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF667EEA),
                          side: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.analytics_rounded, size: 20),
                        label: Text(
                          l10n.viewAnalytics ?? 'View Analytics',
                          style: GoogleFonts.figtree(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Approval message for mobile
                  if (submission.status == AdStatus.approved) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38A169).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF38A169).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF38A169),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.adApprovedMessage,
                              style: GoogleFonts.figtree(
                                fontSize: 12,
                                color: const Color(0xFF38A169),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Rejection reason for mobile
                  if (submission.status == AdStatus.rejected &&
                      submission.rejectionReason != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53E3E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFE53E3E).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFE53E3E),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              submission.rejectionReason!,
                              style: GoogleFonts.figtree(
                                fontSize: 12,
                                color: const Color(0xFFE53E3E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Payment button for mobile - hide for viewers
                  if (!_isViewer &&
                      submission.status == AdStatus.approved &&
                      submission.paymentLink != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DynamicPaymentScreen(
                                submissionId: submission.id,
                                adType: submission.adType.name,
                                duration: submission.duration.name,
                                price: submission.price!,
                                imageUrl: submission.imageUrl,
                                shopName: submission.shopName,
                                paymentLink: submission.paymentLink!,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38A169),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.payment_rounded, size: 20),
                        label: Text(
                          '${l10n.proceedToPayment} (${submission.price!.toStringAsFixed(0)} TL)',
                          style: GoogleFonts.figtree(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCountdownBadge(
    AdSubmission submission,
    AppLocalizations l10n,
    bool isDark, {
    bool isTablet = false,
  }) {
    final remainingTime = _getRemainingTime(submission, l10n);

    if (remainingTime.isEmpty) return const SizedBox.shrink();

    final double paddingH = isTablet ? 6.0 : 10.0;
    final double paddingV = isTablet ? 3.0 : 5.0;
    final double fontSize = isTablet ? 9.0 : 11.0;
    final double iconSize = isTablet ? 10.0 : 14.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: const Color(0xFFED8936).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFED8936).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: iconSize,
            color: const Color(0xFFED8936),
          ),
          const SizedBox(width: 4),
          Text(
            remainingTime,
            style: GoogleFonts.figtree(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFED8936),
            ),
          ),
        ],
      ),
    );
  }

  String _getRemainingTime(AdSubmission submission, AppLocalizations l10n) {
    if (submission.expiresAt == null) return '';

    final now = DateTime.now();
    final expiryDate = submission.expiresAt!.toDate();

    // If expired, return empty
    if (now.isAfter(expiryDate)) return '';

    final difference = expiryDate.difference(now);

    // Calculate weeks, days, hours
    final weeks = difference.inDays ~/ 7;
    final days = difference.inDays % 7;
    final hours = difference.inHours % 24;

    // Return the largest non-zero unit
    if (weeks > 0) {
      return '${weeks}${l10n.weekShort ?? 'W'}';
    } else if (days > 0) {
      return '${days}${l10n.dayShort ?? 'D'}';
    } else if (hours > 0) {
      return '${hours}${l10n.hourShort ?? 'h'}';
    } else {
      final minutes = difference.inMinutes % 60;
      return '${minutes}${l10n.minuteShort ?? 'm'}';
    }
  }

  String _getAdTypeLabel(AdType type, AppLocalizations l10n) {
    switch (type) {
      case AdType.topBanner:
        return l10n.topBanner;
      case AdType.thinBanner:
        return l10n.thinBanner;
      case AdType.marketBanner:
        return l10n.marketBanner;
    }
  }

  String _getDurationLabel(AdDuration duration, AppLocalizations l10n) {
    switch (duration) {
      case AdDuration.oneWeek:
        return l10n.oneWeek;
      case AdDuration.twoWeeks:
        return l10n.twoWeeks;
      case AdDuration.oneMonth:
        return l10n.oneMonth;
    }
  }

  Widget _buildStatusBadge(AdStatus status, AppLocalizations l10n,
      {bool isTablet = false}) {
    final config = _getStatusConfig(status, l10n);
    final double paddingH = isTablet ? 6.0 : 10.0;
    final double paddingV = isTablet ? 3.0 : 5.0;
    final double fontSize = isTablet ? 9.0 : 11.0;
    final double iconSize = isTablet ? 10.0 : 14.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: config['color'].withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            config['icon'] as IconData,
            size: iconSize,
            color: config['color'],
          ),
          const SizedBox(width: 4),
          Text(
            config['text'] as String,
            style: GoogleFonts.figtree(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: config['color'],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdTypeBadge(AdType type, AppLocalizations l10n, bool isDark,
      {bool isTablet = false}) {
    final config = _getAdTypeConfig(type, l10n);
    final double paddingH = isTablet ? 6.0 : 10.0;
    final double paddingV = isTablet ? 3.0 : 5.0;
    final double fontSize = isTablet ? 9.0 : 11.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: (config['color'] as Color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        config['text'] as String,
        style: GoogleFonts.figtree(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: config['color'] as Color,
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(
      AdStatus status, AppLocalizations l10n) {
    switch (status) {
      case AdStatus.pending:
        return {
          'text': l10n.pending,
          'color': const Color(0xFFED8936),
          'icon': Icons.schedule_rounded,
        };
      case AdStatus.approved:
        return {
          'text': l10n.approved,
          'color': const Color(0xFF38A169),
          'icon': Icons.check_circle_rounded,
        };
      case AdStatus.rejected:
        return {
          'text': l10n.rejected,
          'color': const Color(0xFFE53E3E),
          'icon': Icons.cancel_rounded,
        };
      case AdStatus.paid:
        return {
          'text': l10n.paid,
          'color': const Color(0xFF667EEA),
          'icon': Icons.payment_rounded,
        };
      case AdStatus.active:
        return {
          'text': l10n.active,
          'color': const Color(0xFF38A169),
          'icon': Icons.visibility_rounded,
        };
    }
  }

  Map<String, dynamic> _getAdTypeConfig(AdType type, AppLocalizations l10n) {
    switch (type) {
      case AdType.topBanner:
        return {
          'text': l10n.topBanner,
          'color': const Color(0xFF667EEA),
        };
      case AdType.thinBanner:
        return {
          'text': l10n.thinBanner,
          'color': const Color(0xFFED8936),
        };
      case AdType.marketBanner:
        return {
          'text': l10n.marketBanner,
          'color': const Color(0xFF9F7AEA),
        };
    }
  }

  Color _getStatusColor(AdStatus status) {
    switch (status) {
      case AdStatus.pending:
        return const Color(0xFFED8936);
      case AdStatus.approved:
        return const Color(0xFF38A169);
      case AdStatus.rejected:
        return const Color(0xFFE53E3E);
      case AdStatus.paid:
        return const Color(0xFF667EEA);
      case AdStatus.active:
        return const Color(0xFF38A169);
    }
  }

  double _getAspectRatio(AdType type) {
    switch (type) {
      case AdType.topBanner:
        return 24 / 9;
      case AdType.thinBanner:
        return 24 / 9;
      case AdType.marketBanner:
        return 2;
    }
  }

  String _formatDate(Timestamp timestamp, AppLocalizations l10n) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return l10n.today;
    } else if (difference.inDays == 1) {
      return l10n.yesterday;
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ${l10n.daysAgoText}';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }

  Widget _buildLoadingList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 200,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D3748) : Colors.white,
          borderRadius: BorderRadius.circular(16),
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
                Icons.ad_units_rounded,
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

class UploadProgressModal extends StatefulWidget {
  final String shopName;
  final AdType adType;

  const UploadProgressModal({
    super.key,
    required this.shopName,
    required this.adType,
  });

  @override
  State<UploadProgressModal> createState() => _UploadProgressModalState();
}

class _UploadProgressModalState extends State<UploadProgressModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;
  String _currentStage = '';
  double _targetProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void updateProgress(double progress, String stage) {
    setState(() {
      _currentStage = stage;
      _targetProgress = progress;
    });

    _progressAnimation = Tween<double>(
      begin: _progressAnimation.value,
      end: progress,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async => false, // Prevent dismissal
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1A1B23), const Color(0xFF2D3748)]
                  : [Colors.white, const Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF4A5568).withOpacity(0.3)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getAdTypeColor(widget.adType),
                            _getAdTypeColor(widget.adType).withOpacity(0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_upload_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                l10n.uploadingAd,
                style: GoogleFonts.figtree(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 8),

              // Shop Name
              Text(
                widget.shopName,
                style: GoogleFonts.figtree(
                  fontSize: 14,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Progress Bar Container
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2D3748)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progressAnimation.value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _getAdTypeColor(widget.adType),
                              _getAdTypeColor(widget.adType).withOpacity(0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Progress Percentage & Stage
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _currentStage,
                        key: ValueKey(_currentStage),
                        style: GoogleFonts.figtree(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      return Text(
                        '${(_progressAnimation.value * 100).toInt()}%',
                        style: GoogleFonts.figtree(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _getAdTypeColor(widget.adType),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Pulsing dots animation
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 400 + (index * 100)),
                    builder: (context, value, child) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color:
                              _getAdTypeColor(widget.adType).withOpacity(value),
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getAdTypeColor(AdType type) {
    switch (type) {
      case AdType.topBanner:
        return const Color(0xFF667EEA);
      case AdType.thinBanner:
        return const Color(0xFFED8936);
      case AdType.marketBanner:
        return const Color(0xFF9F7AEA);
    }
  }
}
// Add this new widget to your ads_screen.dart file

class AdLinkSelectionSheet extends StatefulWidget {
  final String shopId;
  final String shopName;
  final Function(
          String? linkType, String? linkedShopId, String? linkedProductId)
      onLinkSelected;

  const AdLinkSelectionSheet({
    super.key,
    required this.shopId,
    required this.shopName,
    required this.onLinkSelected,
  });

  @override
  State<AdLinkSelectionSheet> createState() => _AdLinkSelectionSheetState();
}

class _AdLinkSelectionSheetState extends State<AdLinkSelectionSheet> {
  String? _selectedLinkType; // 'shop', 'product', or null (no link)
  String? _selectedProductId;
  List<Product> _products = [];
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_products')
          .where('shopId', isEqualTo: widget.shopId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      _products =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();
    } catch (e) {
      debugPrint('Error loading products: $e');
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                color: const Color(0xFF667EEA),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.addLinkOptional,
                  style: GoogleFonts.figtree(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A202C),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.chooseAdDestination,
            style: GoogleFonts.figtree(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),

          // No Link Option
          _buildLinkOption(
            l10n,
            isDark,
            l10n.noLink,
            l10n.noLinkDescription,
            Icons.block_rounded,
            null,
            _selectedLinkType == null,
          ),
          const SizedBox(height: 12),

          // Shop Link Option
          _buildLinkOption(
            l10n,
            isDark,
            l10n.linkToShop,
            l10n.navigateToShop(widget.shopName),
            Icons.store_rounded,
            'shop',
            _selectedLinkType == 'shop',
          ),
          const SizedBox(height: 12),

          // Product Link Option
          _buildLinkOption(
            l10n,
            isDark,
            l10n.linkToProduct,
            l10n.chooseSpecificProduct,
            Icons.inventory_2_rounded,
            'product',
            _selectedLinkType == 'product',
          ),

          // Product Selector (shown when product link is selected)
          if (_selectedLinkType == 'product') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF2D3748) : const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isLoadingProducts
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                      ? Text(
                          l10n.noProductsAvailable,
                          style: GoogleFonts.figtree(
                            fontSize: 13,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        )
                      : DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedProductId,
                          hint: Text(l10n.selectProduct),
                          items: _products.map((product) {
                            return DropdownMenuItem<String>(
                              value: product.id,
                              child: Text(
                                product.productName,
                                style: GoogleFonts.figtree(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedProductId = value);
                          },
                        ),
            ),
          ],

          const SizedBox(height: 24),

          // Continue Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canContinue() ? _handleContinue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: Text(
                l10n.continueText,
                style: GoogleFonts.figtree(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildLinkOption(
    AppLocalizations l10n,
    bool isDark,
    String title,
    String subtitle,
    IconData icon,
    String? linkType,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLinkType = linkType;
          if (linkType != 'product') {
            _selectedProductId = null;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF667EEA).withOpacity(0.1)
              : isDark
                  ? const Color(0xFF2D3748)
                  : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF667EEA)
                : isDark
                    ? const Color(0xFF4A5568)
                    : const Color(0xFFE2E8F0),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF667EEA)
                    : isDark
                        ? const Color(0xFF4A5568)
                        : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.figtree(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF667EEA),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  bool _canContinue() {
    if (_selectedLinkType == null) return true; // No link is valid
    if (_selectedLinkType == 'shop') return true;
    if (_selectedLinkType == 'product') return _selectedProductId != null;
    return false;
  }

  void _handleContinue() {
    widget.onLinkSelected(
      _selectedLinkType,
      _selectedLinkType == 'shop' ? widget.shopId : null,
      _selectedLinkType == 'product' ? _selectedProductId : null,
    );
    Navigator.pop(context);
  }
}

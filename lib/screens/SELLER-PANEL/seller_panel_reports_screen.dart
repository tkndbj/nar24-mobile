import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/seller_panel_provider.dart';
import '../../../constants/all_in_one_category_data.dart';

// Modern color palette matching your existing design
const Color primaryAccent = Color(0xFF6366F1); // Indigo
const Color successColor = Color(0xFF10B981); // Emerald
const Color warningColor = Color(0xFFF59E0B); // Amber
const Color errorColor = Color(0xFFEF4444); // Red
const Color neutralColor = Color(0xFF6B7280); // Gray

enum ProductSortBy {
  date,
  purchaseCount,
  clickCount,
  favoritesCount,
  cartCount,
  price,
}

enum OrderSortBy {
  date,
  price,
}

enum BoostSortBy {
  date,
  duration,
  price,
  impressionCount,
  clickCount,
}

class ReportConfiguration {
  bool includeProducts;
  String? productCategory;
  String? productSubcategory;
  String? productSubsubcategory;
  ProductSortBy productSortBy;
  bool productSortDescending;

  bool includeOrders;
  OrderSortBy orderSortBy;
  bool orderSortDescending;

  bool includeBoostHistory;
  BoostSortBy boostSortBy;
  bool boostSortDescending;

  DateTimeRange? dateRange;
  String reportName;

  ReportConfiguration({
    this.includeProducts = false,
    this.productCategory,
    this.productSubcategory,
    this.productSubsubcategory,
    this.productSortBy = ProductSortBy.date,
    this.productSortDescending = true,
    this.includeOrders = false,
    this.orderSortBy = OrderSortBy.date,
    this.orderSortDescending = true,
    this.includeBoostHistory = false,
    this.boostSortBy = BoostSortBy.date,
    this.boostSortDescending = true,
    this.dateRange,
    this.reportName = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'includeProducts': includeProducts,
      'productCategory': productCategory,
      'productSubcategory': productSubcategory,
      'productSubsubcategory': productSubsubcategory,
      'productSortBy': productSortBy.name,
      'productSortDescending': productSortDescending,
      'includeOrders': includeOrders,
      'orderSortBy': orderSortBy.name,
      'orderSortDescending': orderSortDescending,
      'includeBoostHistory': includeBoostHistory,
      'boostSortBy': boostSortBy.name,
      'boostSortDescending': boostSortDescending,
      'dateRange': dateRange != null
          ? {
              'start': Timestamp.fromDate(dateRange!.start),
              'end': Timestamp.fromDate(dateRange!.end),
            }
          : null,
      'reportName': reportName,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory ReportConfiguration.fromMap(Map<String, dynamic> map) {
    return ReportConfiguration(
      includeProducts: map['includeProducts'] ?? false,
      productCategory: map['productCategory'],
      productSubcategory: map['productSubcategory'],
      productSubsubcategory: map['productSubsubcategory'],
      productSortBy: ProductSortBy.values.firstWhere(
        (e) => e.name == map['productSortBy'],
        orElse: () => ProductSortBy.date,
      ),
      productSortDescending: map['productSortDescending'] ?? true,
      includeOrders: map['includeOrders'] ?? false,
      orderSortBy: OrderSortBy.values.firstWhere(
        (e) => e.name == map['orderSortBy'],
        orElse: () => OrderSortBy.date,
      ),
      orderSortDescending: map['orderSortDescending'] ?? true,
      includeBoostHistory: map['includeBoostHistory'] ?? false,
      boostSortBy: BoostSortBy.values.firstWhere(
        (e) => e.name == map['boostSortBy'],
        orElse: () => BoostSortBy.date,
      ),
      boostSortDescending: map['boostSortDescending'] ?? true,
      dateRange: map['dateRange'] != null
          ? DateTimeRange(
              start: (map['dateRange']['start'] as Timestamp).toDate(),
              end: (map['dateRange']['end'] as Timestamp).toDate(),
            )
          : null,
      reportName: map['reportName'] ?? '',
    );
  }
}

class SellerPanelReportsScreen extends StatefulWidget {
  final String shopId;

  const SellerPanelReportsScreen({
    Key? key,
    required this.shopId,
  }) : super(key: key);

  @override
  State<SellerPanelReportsScreen> createState() =>
      _SellerPanelReportsScreenState();
}

class _SellerPanelReportsScreenState extends State<SellerPanelReportsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFormat = DateFormat('MMM d, y');
  final ScrollController _scrollController = ScrollController();

  // Report configuration
  ReportConfiguration _config = ReportConfiguration();
  final TextEditingController _reportNameController = TextEditingController();

  final TextEditingController _emailController = TextEditingController();
  bool _isSendingEmail = false;

  // State management
  bool _isGeneratingReport = false;
  bool _isLoadingReports = true;
  List<QueryDocumentSnapshot> _existingReports = [];

  // Safety timer to prevent stuck shimmer
  Timer? _loadingSafetyTimer;
  static const Duration _maxLoadingDuration = Duration(seconds: 15);

  // Viewer role state
  bool _isViewer = false;

  @override
  void initState() {
    super.initState();
    _startLoadingSafetyTimer();
    _checkUserRole();
    _loadExistingReports();
    _loadUserEmail();
  }

  /// Checks if the current user has only viewer role for the shop.
  Future<void> _checkUserRole() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      final shopDoc = await _firestore
          .collection('shops')
          .doc(widget.shopId)
          .get();

      if (shopDoc.exists && mounted) {
        final shopData = shopDoc.data();
        if (shopData != null) {
          final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
          setState(() {
            _isViewer = viewers.contains(currentUserId);
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking user role: $e');
    }
  }

  @override
  void dispose() {
    _loadingSafetyTimer?.cancel();
    _reportNameController.dispose();
    _emailController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Starts a safety timer to prevent shimmer from getting stuck
  void _startLoadingSafetyTimer() {
    _loadingSafetyTimer?.cancel();
    _loadingSafetyTimer = Timer(_maxLoadingDuration, () {
      if (mounted && _isLoadingReports) {
        debugPrint('⚠️ Reports loading safety timer triggered');
        setState(() => _isLoadingReports = false);
      }
    });
  }

  /// Safely end loading state
  void _endLoading() {
    _loadingSafetyTimer?.cancel();
    if (mounted && _isLoadingReports) {
      setState(() => _isLoadingReports = false);
    }
  }

  String? _safeLocalizeCategory(String categoryKey, AppLocalizations l10n) {
    try {
      if (categoryKey.isEmpty) return null;
      return AllInOneCategoryData.localizeCategoryKey(categoryKey, l10n);
    } catch (e) {
      debugPrint('Error localizing category: $e');
      return categoryKey; // Fallback to original key
    }
  }

  String? _safeLocalizeSubcategory(
      String categoryKey, String subcategoryKey, AppLocalizations l10n) {
    try {
      if (categoryKey.isEmpty || subcategoryKey.isEmpty) return null;
      return AllInOneCategoryData.localizeSubcategoryKey(
          categoryKey, subcategoryKey, l10n);
    } catch (e) {
      debugPrint('Error localizing subcategory: $e');
      return subcategoryKey; // Fallback to original key
    }
  }

  String? _safeLocalizeSubSubcategory(String categoryKey, String subcategoryKey,
      String subsubcategoryKey, AppLocalizations l10n) {
    try {
      if (categoryKey.isEmpty ||
          subcategoryKey.isEmpty ||
          subsubcategoryKey.isEmpty) return null;
      return AllInOneCategoryData.localizeSubSubcategoryKey(
          categoryKey, subcategoryKey, subsubcategoryKey, l10n);
    } catch (e) {
      debugPrint('Error localizing subsubcategory: $e');
      return subsubcategoryKey; // Fallback to original key
    }
  }

Future<void> _loadUserEmail() async {
  try {
    final currentUser = Provider.of<SellerPanelProvider>(context, listen: false);
    if (currentUser.userId.isNotEmpty) {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.userId)
          .get();

      if (!mounted) return;

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        _emailController.text = userData['email'] ?? '';
      }
    }
  } catch (e) {
    debugPrint('Error loading user email: $e');
  }
}

void _showEmailModal(QueryDocumentSnapshot reportDoc) {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final data = reportDoc.data() as Map<String, dynamic>;
  final config = ReportConfiguration.fromMap(data);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2840) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modal handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[600] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Icon and title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.email_outlined,
                            color: primaryAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.sendReportByEmail ?? 'Send Report by Email',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                  fontFamily: 'Figtree',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.reportWillBeSentToEmail ?? 
                                    'Your report will be sent to the email below',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontFamily: 'Figtree',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Email input field
                    Text(
                      l10n.emailAddress ?? 'Email Address',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        fontFamily: 'Figtree',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1A29)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 15,
                          fontFamily: 'Figtree',
                        ),
                        decoration: InputDecoration(
                          hintText:
                              l10n.enterEmailAddress ?? 'Enter email address',
                          hintStyle: TextStyle(
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[400],
                            fontFamily: 'Figtree',
                          ),
                          prefixIcon: Icon(
                            Icons.mail_outline,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[600],
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Report preview
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1A29).withOpacity(0.5)
                            : primaryAccent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primaryAccent.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.analytics_rounded,
                            color: primaryAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  config.reportName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isDark ? Colors.white : Colors.black,
                                    fontFamily: 'Figtree',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${l10n.reportId ?? "Report ID"}: #${reportDoc.id.substring(0, 8).toUpperCase()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    fontFamily: 'Figtree',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSendingEmail
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.grey[600]!
                                    : Colors.grey[300]!,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              l10n.cancel ?? 'Cancel',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Figtree',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSendingEmail
                                ? null
                                : () async {
                                    if (_emailController.text.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(l10n
                                                  .pleaseEnterEmail ??
                                              'Please enter an email address'),
                                          backgroundColor: warningColor,
                                        ),
                                      );
                                      return;
                                    }

                                    setModalState(() {
                                      _isSendingEmail = true;
                                    });

                                    final success = await _sendReportByEmail(
                                      reportDoc.id,
                                      _emailController.text,
                                    );

                                    setModalState(() {
                                      _isSendingEmail = false;
                                    });

                                    if (success) {
                                      Navigator.pop(context);
                                      _showSuccessSnackbar(
                                        l10n.reportSentSuccessfully ??
                                            'Report sent successfully!',
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryAccent,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isSendingEmail
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    l10n.sendEmail ?? 'Send Email',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Figtree',
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<bool> _sendReportByEmail(String reportId, String email) async {
  try {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
    final callable = functions.httpsCallable('sendReportEmail');

    final result = await callable.call({
      'reportId': reportId,
      'shopId': widget.shopId,
      'email': email,
    });

    // Check if successful
    if (result.data['success'] == true) {
      return true;
    } else {
      throw Exception('Failed to send email');
    }
  } catch (e) {
    debugPrint('Error sending report email: $e');
    _showErrorSnackbar('Failed to send email. Please try again.');
    return false;
  }
}

  Future<void> _loadExistingReports() async {
    try {
      final querySnapshot = await _firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .get();

      if (!mounted) return;

      setState(() {
        _existingReports = querySnapshot.docs;
      });
      _endLoading();
    } catch (e) {
      debugPrint('Error loading reports: $e');
      _endLoading();
      if (mounted) {
        _showErrorSnackbar('Failed to load existing reports');
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

 void _showLoadingModal() {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Loading animation
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
                ),
              ),
              const SizedBox(height: 24),
              // Loading text
              Text(
                l10n.generatingReport ?? 'Generating Report...',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.processingLargeDatasets ??
                    'Processing large datasets on our servers',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontFamily: 'Figtree',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.thisMayTakeAFewMinutes ??
                    'This may take a few minutes for large reports',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontFamily: 'Figtree',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    },
  );
}

  void _hideLoadingModal() {
    Navigator.of(context).pop();
  }

  Future<void> _generateReport() async {
  final l10n = AppLocalizations.of(context);

  if (_reportNameController.text.trim().isEmpty) {
    _showErrorSnackbar(
        l10n.pleaseEnterReportName ?? 'Please enter a report name');
    return;
  }

  if (!_config.includeProducts &&
      !_config.includeOrders &&
      !_config.includeBoostHistory) {
    _showErrorSnackbar(l10n.pleaseSelectAtLeastOneDataType ??
        'Please select at least one data type to include');
    return;
  }

  setState(() {
    _isGeneratingReport = true;
  });

  // Show loading modal
  _showLoadingModal();

  String? reportDocId;

  try {
    _config.reportName = _reportNameController.text.trim();

    // Step 1: Create initial report document with pending status
    final reportDoc = await _firestore
        .collection('shops')
        .doc(widget.shopId)
        .collection('reports')
        .add({
      ..._config.toMap(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    reportDocId = reportDoc.id;

    // Step 2: Call Cloud Function to generate PDF
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('generatePDFReport');

      final result = await callable.call({
        'reportId': reportDocId,
        'shopId': widget.shopId,
      });

      // Check if successful
      if (result.data['success'] == true) {
        // The cloud function has already updated the report document
        // Just refresh the reports list
        await _loadExistingReports();

        // Clear form
        _reportNameController.clear();
        _config = ReportConfiguration();

        setState(() {
          _isGeneratingReport = false;
        });

        // Hide loading modal
        _hideLoadingModal();

        _showSuccessSnackbar(
            l10n.reportGeneratedSuccessfully ?? 'Report generated successfully!');
      } else {
        throw Exception('Report generation failed');
      }
    } catch (e) {
      debugPrint('Error calling cloud function: $e');
      
      // Update report status to failed
      await reportDoc.update({
        'status': 'failed',
        'error': e.toString(),
        'failedAt': FieldValue.serverTimestamp(),
      });
      
      throw e;
    }
  } catch (e) {
    debugPrint('Error generating report: $e');

    setState(() {
      _isGeneratingReport = false;
    });

    // Hide loading modal
    _hideLoadingModal();

    _showErrorSnackbar('Failed to generate report: ${_getUserFriendlyError(e)}');
  }
}

// Convert technical errors to user-friendly messages
String _getUserFriendlyError(dynamic error) {
  final errorString = error.toString().toLowerCase();
  
  if (errorString.contains('permission')) {
    return 'Permission denied. Please check your access rights.';
  } else if (errorString.contains('network')) {
    return 'Network error. Please check your connection.';
  } else if (errorString.contains('storage')) {
    return 'Storage error. Please try again later.';
  } else if (errorString.contains('memory')) {
    return 'The report is too large. Try selecting a smaller date range.';
  } else {
    return 'An unexpected error occurred. Please try again.';
  }
} 

 Future<void> _downloadReport(QueryDocumentSnapshot reportDoc) async {
  // Changed to show email modal instead of downloading
  _showEmailModal(reportDoc);
}

  String _getLocalizedSortByText(dynamic sortBy, AppLocalizations l10n) {
    if (sortBy is ProductSortBy) {
      switch (sortBy) {
        case ProductSortBy.date:
          return l10n.sortByDate ?? 'Date';
        case ProductSortBy.purchaseCount:
          return l10n.sortByPurchaseCount ?? 'Purchase Count';
        case ProductSortBy.clickCount:
          return l10n.sortByClickCount ?? 'Click Count';
        case ProductSortBy.favoritesCount:
          return l10n.sortByFavoritesCount ?? 'Favorites Count';
        case ProductSortBy.cartCount:
          return l10n.sortByCartCount ?? 'Cart Count';
        case ProductSortBy.price:
          return l10n.sortByPrice ?? 'Price';
      }
    } else if (sortBy is OrderSortBy) {
      switch (sortBy) {
        case OrderSortBy.date:
          return l10n.sortByDate ?? 'Date';
        case OrderSortBy.price:
          return l10n.sortByPrice ?? 'Price';
      }
    } else if (sortBy is BoostSortBy) {
      switch (sortBy) {
        case BoostSortBy.date:
          return l10n.sortByDate ?? 'Date';
        case BoostSortBy.duration:
          return l10n.sortByDuration ?? 'Duration';
        case BoostSortBy.price:
          return l10n.sortByPrice ?? 'Price';
        case BoostSortBy.impressionCount:
          return l10n.sortByImpressionCount ?? 'Impression Count';
        case BoostSortBy.clickCount:
          return l10n.sortByClickCount ?? 'Click Count';
      }
    }
    return '';
  } 

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Color(0xFF1C1A29) : Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          l10n.reports ?? 'Reports',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.grey[900],
            fontWeight: FontWeight.w600,
            fontSize: 20,
            fontFamily: 'Figtree',
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.grey[900],
        ),
      ),
      body: SafeArea(
        top: false,
        child: _isLoadingReports
            ? _buildLoadingShimmer(isDark)
            : SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Create New Report Section - hidden for viewers
                    if (!_isViewer) ...[
                      _buildCreateReportSection(isDark),
                      const SizedBox(height: 24),
                    ],

                    // Existing Reports Section
                    _buildExistingReportsSection(isDark),
                  ],
                ),
              ),
      ),
    );
  }

  /// Builds shimmer placeholder while reports are loading
  Widget _buildLoadingShimmer(bool isDark) {
    final baseColor = isDark
        ? const Color.fromARGB(255, 30, 28, 44)
        : Colors.grey[300]!;
    final highlightColor = isDark
        ? const Color.fromARGB(255, 45, 42, 65)
        : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Create Report Section Shimmer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 16,
                              width: 140,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 12,
                              width: 200,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Input field shimmer
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Date range shimmer
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Toggle items shimmer
                  ...List.generate(3, (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )),
                  const SizedBox(height: 8),
                  // Button shimmer
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Existing Reports Header Shimmer
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 18,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Report cards shimmer
            ...List.generate(3, (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateReportSection(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.grey).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.analytics_rounded,
                  color: primaryAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.createNewReport ?? 'Create New Report',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.grey[900],
                        fontFamily: 'Figtree',
                      ),
                    ),
                    Text(
                      l10n.generateCustomReportsForYourShop ??
                          'Generate custom reports for your shop',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontFamily: 'Figtree',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Report Name Input
          _buildTextInput(
            controller: _reportNameController,
            label: l10n.reportName ?? 'Report Name',
            hint: l10n.enterReportName ?? 'Enter report name...',
            isDark: isDark,
          ),

          const SizedBox(height: 16),

          // Date Range Selector
          _buildDateRangeSelector(isDark),

          const SizedBox(height: 16),

          // Data Type Selection
          Text(
            l10n.selectDataToInclude ?? 'Select Data to Include',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
          ),

          const SizedBox(height: 12),

          // Products Toggle
          _buildDataTypeToggle(
            title: l10n.products ?? 'Products',
            subtitle:
                l10n.includeProductInformation ?? 'Include product information',
            value: _config.includeProducts,
            onChanged: (value) {
              setState(() {
                _config.includeProducts = value;
                if (!value) {
                  _config.productCategory = null;
                  _config.productSubcategory = null;
                  _config.productSubsubcategory = null;
                }
              });
            },
            icon: Icons.inventory_2_rounded,
            color: successColor,
            isDark: isDark,
          ),

          // Product Filters and Sort Options
          if (_config.includeProducts) ...[
            const SizedBox(height: 12),
            _buildProductFilters(isDark),
            const SizedBox(height: 12),
            _buildProductSortOptions(isDark),
          ],

          const SizedBox(height: 12),

          // Orders Toggle
          _buildDataTypeToggle(
            title: l10n.orders ?? 'Orders',
            subtitle:
                l10n.includeOrderInformation ?? 'Include order information',
            value: _config.includeOrders,
            onChanged: (value) {
              setState(() {
                _config.includeOrders = value;
              });
            },
            icon: Icons.shopping_bag_rounded,
            color: warningColor,
            isDark: isDark,
          ),

          // Order Sort Options
          if (_config.includeOrders) ...[
            const SizedBox(height: 12),
            _buildOrderSortOptions(isDark),
          ],

          const SizedBox(height: 12),

          // Boost History Toggle
          _buildDataTypeToggle(
            title: l10n.boostHistory ?? 'Boost History',
            subtitle:
                l10n.includeBoostInformation ?? 'Include boost information',
            value: _config.includeBoostHistory,
            onChanged: (value) {
              setState(() {
                _config.includeBoostHistory = value;
              });
            },
            icon: Icons.rocket_launch_rounded,
            color: primaryAccent,
            isDark: isDark,
          ),

          // Boost Sort Options
          if (_config.includeBoostHistory) ...[
            const SizedBox(height: 12),
            _buildBoostSortOptions(isDark),
          ],

          const SizedBox(height: 24),

          // Generate Button
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryAccent, primaryAccent.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _isGeneratingReport ? null : _generateReport,
                child: Container(
                  alignment: Alignment.center,
                  child: _isGeneratingReport
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.analytics_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.generateReport ?? 'Generate Report',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontFamily: 'Figtree',
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSortOptions(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.sortOptions ?? 'Sort Options',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
          ),
          const SizedBox(height: 12),

          // Sort By
          _buildSortBySelector(
            label: l10n.sortBy ?? 'Sort By',
            value: _config.productSortBy,
            options: ProductSortBy.values,
            getDisplayText: (option) => _getLocalizedSortByText(option, l10n),
            onChanged: (value) {
              setState(() {
                _config.productSortBy = value;
              });
            },
            isDark: isDark,
          ),

          const SizedBox(height: 12),

          // Sort Order
          _buildSortOrderToggle(
            isDescending: _config.productSortDescending,
            onChanged: (value) {
              setState(() {
                _config.productSortDescending = value;
              });
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSortOptions(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.sortOptions ?? 'Sort Options',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
          ),
          const SizedBox(height: 12),

          // Sort By
          _buildSortBySelector(
            label: l10n.sortBy ?? 'Sort By',
            value: _config.orderSortBy,
            options: OrderSortBy.values,
            getDisplayText: (option) => _getLocalizedSortByText(option, l10n),
            onChanged: (value) {
              setState(() {
                _config.orderSortBy = value;
              });
            },
            isDark: isDark,
          ),

          const SizedBox(height: 12),

          // Sort Order
          _buildSortOrderToggle(
            isDescending: _config.orderSortDescending,
            onChanged: (value) {
              setState(() {
                _config.orderSortDescending = value;
              });
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildBoostSortOptions(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.sortOptions ?? 'Sort Options',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
          ),
          const SizedBox(height: 12),

          // Sort By
          _buildSortBySelector(
            label: l10n.sortBy ?? 'Sort By',
            value: _config.boostSortBy,
            options: BoostSortBy.values,
            getDisplayText: (option) => _getLocalizedSortByText(option, l10n),
            onChanged: (value) {
              setState(() {
                _config.boostSortBy = value;
              });
            },
            isDark: isDark,
          ),

          const SizedBox(height: 12),

          // Sort Order
          _buildSortOrderToggle(
            isDescending: _config.boostSortDescending,
            onChanged: (value) {
              setState(() {
                _config.boostSortDescending = value;
              });
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSortBySelector<T>({
    required String label,
    required T value,
    required List<T> options,
    required String Function(T) getDisplayText,
    required ValueChanged<T> onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontFamily: 'Figtree',
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showSortByPicker(options, getDisplayText, onChanged),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    getDisplayText(value),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.grey[900],
                      fontFamily: 'Figtree',
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSortOrderToggle({
    required bool isDescending,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Text(
          l10n.sortOrder ?? 'Sort Order',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontFamily: 'Figtree',
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => onChanged(true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDescending
                  ? primaryAccent.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDescending
                    ? primaryAccent
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
              ),
            ),
            child: Text(
              l10n.descending ?? 'Descending',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDescending
                    ? primaryAccent
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                fontFamily: 'Figtree',
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onChanged(false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: !isDescending
                  ? primaryAccent.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: !isDescending
                    ? primaryAccent
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
              ),
            ),
            child: Text(
              l10n.ascending ?? 'Ascending',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: !isDescending
                    ? primaryAccent
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                fontFamily: 'Figtree',
              ),
            ),
          ),
        ),
      ],
    );
  }

 void _showSortByPicker<T>(
  List<T> options,
  String Function(T) getDisplayText,
  ValueChanged<T> onChanged,
) {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textColor = isDark ? Colors.white : Colors.black;

  showCupertinoModalPopup(
    context: context,
    builder: (BuildContext context) {
      return CupertinoActionSheet(
        title: Text(
          l10n.selectSortBy ?? 'Select Sort By',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Figtree',
            color: textColor,
          ),
        ),
        actions: options.map((option) {
          return CupertinoActionSheetAction(
            child: Text(
              getDisplayText(option),
              style: TextStyle(
                fontFamily: 'Figtree',
                color: textColor,
              ),
            ),
            onPressed: () {
              onChanged(option);
              Navigator.pop(context);
            },
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          child: Text(
            l10n.cancel ?? 'Cancel',
            style: TextStyle(
              fontFamily: 'Figtree',
              color: textColor,
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      );
    },
  );
}

  Widget _buildExistingReportsSection(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history_rounded,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.existingReports ?? 'Existing Reports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.grey[900],
                fontFamily: 'Figtree',
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_existingReports.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey[700],
                  fontFamily: 'Figtree',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_existingReports.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.grey).withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: neutralColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    size: 40,
                    color: neutralColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noReportsYet ?? 'No Reports Yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[900],
                    fontFamily: 'Figtree',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.createYourFirstReport ??
                      'Create your first report to get started',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontFamily: 'Figtree',
                  ),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _existingReports.length,
            itemBuilder: (context, index) {
              final report = _existingReports[index];
              final data = report.data() as Map<String, dynamic>;
              final config = ReportConfiguration.fromMap(data);

              return _buildReportCard(report, config, isDark);
            },
          ),
      ],
    );
  }

  Widget _buildReportCard(
      QueryDocumentSnapshot report, ReportConfiguration config, bool isDark) {
    final data = report.data() as Map<String, dynamic>;
    final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.grey).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.description_rounded,
                          color: primaryAccent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.reportName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey[900],
                                fontFamily: 'Figtree',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _dateFormat.format(createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontFamily: 'Figtree',
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Download Button
                      Container(
                        decoration: BoxDecoration(
                          color: successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _downloadReport(report),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.download_rounded,
                                color: successColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Date Range
                  if (config.dateRange != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            size: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_dateFormat.format(config.dateRange!.start)} - ${_dateFormat.format(config.dateRange!.end)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[700],
                              fontFamily: 'Figtree',
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Data Types
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (config.includeProducts)
                        _buildDataTypeBadge(
                          'Products',
                          Icons.inventory_2_rounded,
                          successColor,
                          isDark,
                        ),
                      if (config.includeOrders)
                        _buildDataTypeBadge(
                          'Orders',
                          Icons.shopping_bag_rounded,
                          warningColor,
                          isDark,
                        ),
                      if (config.includeBoostHistory)
                        _buildDataTypeBadge(
                          'Boosts',
                          Icons.rocket_launch_rounded,
                          primaryAccent,
                          isDark,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTypeBadge(
      String label, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'Figtree',
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildTextInput({
  required TextEditingController controller,
  required String label,
  required String hint,
  required bool isDark,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.grey[900],
          fontFamily: 'Figtree',
        ),
      ),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[50],  // CHANGED HERE
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          ),
        ),
          child: TextField(
            controller: controller,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[500],
                fontFamily: 'Figtree',
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeSelector(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dateRange ?? 'Date Range (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[900],
            fontFamily: 'Figtree',
          ),
        ),
        const SizedBox(height: 6),
        Container(
            decoration: BoxDecoration(
    color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[50],  // CHANGED HERE
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
    ),
  ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final dateRange = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _config.dateRange,
                );
                if (dateRange != null) {
                  setState(() {
                    _config.dateRange = dateRange;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_rounded,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _config.dateRange != null
                            ? '${_dateFormat.format(_config.dateRange!.start)} - ${_dateFormat.format(_config.dateRange!.end)}'
                            : l10n.selectDateRange ?? 'Select date range...',
                        style: TextStyle(
                          color: _config.dateRange != null
                              ? (isDark ? Colors.white : Colors.grey[900])
                              : (isDark ? Colors.grey[400] : Colors.grey[500]),
                          fontFamily: 'Figtree',
                        ),
                      ),
                    ),
                    if (_config.dateRange != null)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _config.dateRange = null;
                          });
                        },
                        child: Icon(
                          Icons.clear_rounded,
                          color: isDark ? Colors.grey[400] : Colors.grey[500],
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataTypeToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
        decoration: BoxDecoration(
    color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[50],  // CHANGED HERE
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: value
          ? color.withOpacity(0.5)
          : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
    ),
  ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(!value),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: color,
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.grey[900],
                          fontFamily: 'Figtree',
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontFamily: 'Figtree',
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductFilters(bool isDark) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.productFilters ?? 'Product Filters',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
          ),
          const SizedBox(height: 12),

          // Category Selection - FIXED
          _buildFilterSelector(
            label: l10n.category ?? 'Category',
            value: _config.productCategory,
            displayValue: _config.productCategory != null &&
                    _config.productCategory!.isNotEmpty
                ? _safeLocalizeCategory(_config.productCategory!, l10n)
                : null,
            onTap: () => _showCategoryPicker(),
            isDark: isDark,
          ),

          if (_config.productCategory != null &&
              _config.productCategory!.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Subcategory Selection - FIXED
            _buildFilterSelector(
              label: l10n.subcategory ?? 'Subcategory',
              value: _config.productSubcategory,
              displayValue: _config.productSubcategory != null &&
                      _config.productSubcategory!.isNotEmpty
                  ? _safeLocalizeSubcategory(_config.productCategory!,
                      _config.productSubcategory!, l10n)
                  : null,
              onTap: () => _showSubcategoryPicker(),
              isDark: isDark,
            ),
          ],

          if (_config.productSubcategory != null &&
              _config.productSubcategory!.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Sub-subcategory Selection - FIXED
            _buildFilterSelector(
              label: l10n.subsubcategory ?? 'Sub-subcategory',
              value: _config.productSubsubcategory,
              displayValue: _config.productSubsubcategory != null &&
                      _config.productSubsubcategory!.isNotEmpty
                  ? _safeLocalizeSubSubcategory(
                      _config.productCategory!,
                      _config.productSubcategory!,
                      _config.productSubsubcategory!,
                      l10n)
                  : null,
              onTap: () => _showSubSubcategoryPicker(),
              isDark: isDark,
            ),
          ],

          // Clear filters button (unchanged)
          if (_config.productCategory != null ||
              _config.productSubcategory != null ||
              _config.productSubsubcategory != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                setState(() {
                  _config.productCategory = null;
                  _config.productSubcategory = null;
                  _config.productSubsubcategory = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: errorColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.clear_rounded,
                      size: 16,
                      color: errorColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.clearFilters ?? 'Clear Filters',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: errorColor,
                        fontFamily: 'Figtree',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterSelector({
    required String label,
    required String? value,
    required String? displayValue,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontFamily: 'Figtree',
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayValue ??
                        (l10n.selectOption(label) ?? 'Select $label'),
                    style: TextStyle(
                      color: displayValue != null
                          ? (isDark ? Colors.white : Colors.grey[900])
                          : (isDark ? Colors.grey[400] : Colors.grey[500]),
                      fontFamily: 'Figtree',
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

 void _showCategoryPicker() {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textColor = isDark ? Colors.white : Colors.black;

  showCupertinoModalPopup(
    context: context,
    builder: (BuildContext context) {
      return CupertinoActionSheet(
        title: Text(
          l10n.selectCategory ?? 'Select Category',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Figtree',
            color: textColor,
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            child: Text(
              l10n.allCategories ?? 'All Categories',
              style: TextStyle(fontFamily: 'Figtree', color: textColor),
            ),
            onPressed: () {
              setState(() {
                _config.productCategory = null;
                _config.productSubcategory = null;
                _config.productSubsubcategory = null;
              });
              Navigator.pop(context);
            },
          ),
          ...AllInOneCategoryData.kCategories
              .where((category) =>
                  category['key'] != null && category['key']!.isNotEmpty)
              .map((category) {
            final categoryKey = category['key']!;
            final localizedName =
                _safeLocalizeCategory(categoryKey, l10n) ?? categoryKey;

            return CupertinoActionSheetAction(
              child: Text(
                localizedName,
                style: TextStyle(fontFamily: 'Figtree', color: textColor),
              ),
              onPressed: () {
                setState(() {
                  _config.productCategory = categoryKey;
                  _config.productSubcategory = null;
                  _config.productSubsubcategory = null;
                });
                Navigator.pop(context);

                Future.delayed(const Duration(milliseconds: 300), () {
                  _showSubcategoryPicker();
                });
              },
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: Text(
            l10n.cancel ?? 'Cancel',
            style: TextStyle(fontFamily: 'Figtree', color: textColor),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      );
    },
  );
}

 void _showSubcategoryPicker() {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textColor = isDark ? Colors.white : Colors.black;

  if (_config.productCategory == null) return;

  final subcategories =
      AllInOneCategoryData.kSubcategories[_config.productCategory] ?? [];

  showCupertinoModalPopup(
    context: context,
    builder: (BuildContext context) {
      return CupertinoActionSheet(
        title: Text(
          l10n.selectSubcategory ?? 'Select Subcategory',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Figtree',
            color: textColor,
          ),
        ),
        message: Text(
          '${l10n.category ?? 'Category'}: ${AllInOneCategoryData.localizeCategoryKey(_config.productCategory!, l10n)}',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Figtree',
            color: textColor,
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            child: Text(
              l10n.skipSubcategory ?? 'Skip - Show All Products in Category',
              style: TextStyle(
                color: CupertinoColors.systemBlue,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
              ),
            ),
            onPressed: () {
              setState(() {
                _config.productSubcategory = null;
                _config.productSubsubcategory = null;
              });
              Navigator.pop(context);
            },
          ),
          ...subcategories.map((subcategory) {
            final localizedName = AllInOneCategoryData.localizeSubcategoryKey(
                _config.productCategory!, subcategory, l10n);

            return CupertinoActionSheetAction(
              child: Text(
                localizedName,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  color: textColor,
                ),
              ),
              onPressed: () {
                setState(() {
                  _config.productSubcategory = subcategory;
                  _config.productSubsubcategory = null;
                });
                Navigator.pop(context);

                Future.delayed(const Duration(milliseconds: 300), () {
                  _showSubSubcategoryPicker();
                });
              },
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: Text(
            l10n.cancel ?? 'Cancel',
            style: TextStyle(
              fontFamily: 'Figtree',
              color: textColor,
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      );
    },
  );
}

  void _showSubSubcategoryPicker() {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textColor = isDark ? Colors.white : Colors.black;

  if (_config.productCategory == null || _config.productSubcategory == null)
    return;

  final subSubcategories =
      AllInOneCategoryData.kSubSubcategories[_config.productCategory]
              ?[_config.productSubcategory] ??
          [];

  showCupertinoModalPopup(
    context: context,
    builder: (BuildContext context) {
      return CupertinoActionSheet(
        title: Text(
          l10n.selectSubSubcategory ?? 'Select Sub-subcategory',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Figtree',
            color: textColor,
          ),
        ),
        message: Text(
          '${AllInOneCategoryData.localizeCategoryKey(_config.productCategory!, l10n)} > ${AllInOneCategoryData.localizeSubcategoryKey(_config.productCategory!, _config.productSubcategory!, l10n)}',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Figtree',
            color: textColor,
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            child: Text(
              l10n.skipSubSubcategory ??
                  'Skip - Show All Products in Subcategory',
              style: TextStyle(
                color: CupertinoColors.systemBlue,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
              ),
            ),
            onPressed: () {
              setState(() {
                _config.productSubsubcategory = null;
              });
              Navigator.pop(context);
            },
          ),
          ...subSubcategories.map((subSubcategory) {
            final localizedName =
                AllInOneCategoryData.localizeSubSubcategoryKey(
                    _config.productCategory!,
                    _config.productSubcategory!,
                    subSubcategory,
                    l10n);

            return CupertinoActionSheetAction(
              child: Text(
                localizedName,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  color: textColor,
                ),
              ),
              onPressed: () {
                setState(() {
                  _config.productSubsubcategory = subSubcategory;
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: Text(
            l10n.cancel ?? 'Cancel',
            style: TextStyle(
              fontFamily: 'Figtree',
              color: textColor,
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      );
    },
  );
}
}

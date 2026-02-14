import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';
import '../PAYMENT-RECEIPT/shipment_status_screen.dart';
import '../BOOST-SCREENS/boost_screen.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import '../../models/notification.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../PAYMENT-RECEIPT/dynamic_payment_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Pagination variables
  final int _limit = 20;
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  bool _hasMore = true;
  List<NotificationModel> _notifications = [];
  final ScrollController _scrollController = ScrollController();

  // Pull-to-refresh cooldown
  DateTime? _lastRefreshTime;
  final Duration _refreshCooldown = const Duration(seconds: 30);

  // Initial load shimmer state
  bool _isInitialLoad = true;
  Timer? _shimmerSafetyTimer;

  /// Maximum time to show shimmer before forcing completion (safety net)
  static const Duration _maxShimmerDuration = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    if (currentUser != null) {
      // Start safety timer to prevent shimmer getting stuck
      _startShimmerSafetyTimer();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _fetchNotifications(forceRefresh: true);
        if (mounted) {
          _scrollController.addListener(_scrollListener);
        }
      });
    } else {
      // No user = no shimmer needed
      _isInitialLoad = false;
    }
  }

  @override
  void dispose() {
    _shimmerSafetyTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Starts a safety timer to prevent shimmer from getting stuck
  void _startShimmerSafetyTimer() {
    _shimmerSafetyTimer?.cancel();
    _shimmerSafetyTimer = Timer(_maxShimmerDuration, () {
      if (mounted && _isInitialLoad) {
        debugPrint('⚠️ Notification shimmer safety timer triggered');
        setState(() => _isInitialLoad = false);
      }
    });
  }

  /// Safely ends the initial load state
  void _endInitialLoad() {
    _shimmerSafetyTimer?.cancel();
    if (mounted && _isInitialLoad) {
      setState(() => _isInitialLoad = false);
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoading &&
        _hasMore) {
      _fetchNotifications();
    }
  }

  Future<void> _fetchNotifications({bool forceRefresh = false}) async {
    final uid = currentUser?.uid;
    if (uid == null || _isLoading) return;

    if (forceRefresh) {
      _lastDocument = null;
      _hasMore = true;
      _notifications.clear();
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final colRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .withNotificationConverter();

      var q = colRef.orderBy('timestamp', descending: true).limit(_limit);
      if (_lastDocument != null) q = q.startAfterDocument(_lastDocument!);

      final snap = await q.get();

      if (!mounted) return;

      if (snap.docs.isEmpty) {
        setState(() => _hasMore = false);
      } else {
        _lastDocument = snap.docs.last;

        // Filter and dedupe notifications
        final fetched = snap.docs
            .map((d) => d.data())
            .where((n) => n.type != 'message')
            .where((n) => !(n.type == 'shop_invitation' &&
                (n.status == 'accepted' || n.status == 'rejected')))
            .toList();

        setState(() {
          final existingIds = _notifications.map((n) => n.id).toSet();
          final newOnes = fetched.where((n) => !existingIds.contains(n.id));
          _notifications.addAll(newOnes);
          if (snap.docs.length < _limit) _hasMore = false;
        });

        await _markNotificationsAsRead(snap.docs);
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      // Always end initial load when fetch completes (success or error)
      _endInitialLoad();
    }
  }

  Future<void> _handleRefresh() async {
    final now = DateTime.now();

    // Check cooldown
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _refreshCooldown) {
      final remaining = _refreshCooldown.inSeconds -
          now.difference(_lastRefreshTime!).inSeconds;

      if (!mounted) return; // ✅ ADD THIS
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please wait $remaining seconds before refreshing again',
            style: const TextStyle(fontFamily: 'Figtree'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _lastRefreshTime = now;
    await _fetchNotifications(forceRefresh: true);
  }

  Future<void> _markNotificationsAsRead(
    List<QueryDocumentSnapshot<NotificationModel>> docs,
  ) async {
    final batch = _firestore.batch();

    for (final docSnap in docs) {
      final notif = docSnap.data();
      if (!notif.isRead) {
        batch.update(docSnap.reference, {'isRead': true});
      }
    }

    try {
      await batch.commit();
    } catch (e) {
      print('Error marking notifications as read: $e');
    }
  }

  Future<void> _deleteNotification(String docId) async {
    try {
      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('notifications')
          .doc(docId)
          .delete();

      if (!mounted) return; // ✅ ADD THIS

      setState(() {
        _notifications.removeWhere((notification) => notification.id == docId);
      });

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.notificationDeletedSuccessfully)),
      );
    } catch (e) {
      if (!mounted) return; // ✅ ADD THIS
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorOccurredWithDetails(e.toString()))),
      );
    }
  }

  Future<void> _handleInvitationResponse(
    NotificationModel notification, {
    required bool accepted,
  }) async {
    final l10n = AppLocalizations.of(context);

    if (!accepted) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
            .httpsCallable('handleShopInvitation');

        await callable.call({
          'notificationId': notification.id,
          'accepted': false,
          'shopId': notification.shopId,
          'role': notification.role,
        });

        if (!mounted) return;

        setState(() {
          _notifications.removeWhere((n) => n.id == notification.id);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.invitationRejected)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorOccurredWithDetails(e.toString()))),
        );
      }
      return;
    }

    _showInvitationAcceptingModal(notification.shopName ?? 'shop');

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('handleShopInvitation');

      await callable.call({
        'notificationId': notification.id,
        'accepted': true,
        'shopId': notification.shopId,
        'role': notification.role,
      });

      if (context.mounted) {
        setState(() {
          _notifications.removeWhere((n) => n.id == notification.id);
        });

        Navigator.of(context).pop();

        if (notification.shopId != null) {
          context.push('/seller-panel?shopId=${notification.shopId}&tab=0');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.errorOccurredWithDetails(e.toString())),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  void _showInvitationAcceptingModal(String shopName) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
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
                          colors: [Color(0xFF00A86B), Color(0xFF00D68F)],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.store_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                l10n.joiningShop ?? 'Joining shop...',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                shopName,
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
                            Color(0xFF00A86B)),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleNotificationTap(NotificationModel notification) async {
    final l10n = AppLocalizations.of(context);
    final type = notification.type;

    switch (type) {
      case 'boosted':
      case 'boost_expired':
        final itemType = notification.itemType ?? '';
        final productId = notification.productId;
        final shopId = notification.shopId;

        if (itemType == 'product' && productId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BoostScreen(productId: productId),
            ),
          );
        } else if (itemType == 'shop_product' && shopId != null) {
          context.pushReplacement('/seller-panel?shopId=$shopId&tab=5');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.itemInfoNotFound)),
          );
        }
        break;

      case 'order_delivered':
        final orderId = notification.orderId;
        if (orderId != null) {
          context.push('/my-reviews');
        } else {
          context.push('/my-reviews');
        }
        break;

      case 'product_archived_by_admin':
        context.push('/archived-products');
        break;

      case 'refund_request_approved':
        showDialog(
          context: context,
          builder: (context) {
            final textColor = Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black;
            return CupertinoAlertDialog(
              title: Text(
                l10n.refundRequestApprovedTitle,
                style: const TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 18.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.center, // ✅ Changed from start to center
                children: [
                  const SizedBox(height: 8),
                  Text(
                    l10n.refundRequestApprovedMessage,
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16.0,
                    ),
                    textAlign: TextAlign.center, // ✅ Added text alignment
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.refundOfficeAddress,
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 14.0,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign:
                                TextAlign.center, // ✅ Added text alignment
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.ok,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
        break;

      case 'product_question_answered':
        context.push('/user-product-questions');
        break;

      case 'refund_request_rejected':
        final rejectionReason = notification.rejectionReason;
        showDialog(
          context: context,
          builder: (context) {
            final textColor = Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black;
            return CupertinoAlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.center, // ✅ Changed from start to center
                children: [
                  Text(
                    l10n.refundRequestRejectedMessage,
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center, // ✅ Added text alignment
                  ),
                  if (rejectionReason != null &&
                      rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.rejectionReason,
                      style: const TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center, // ✅ Added text alignment
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        rejectionReason,
                        style: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 16.0,
                        ),
                        textAlign: TextAlign.center, // ✅ Added text alignment
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.done,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
        break;

      case 'ad_approved':
        final submissionId = notification.submissionId;

        if (submissionId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(l10n.submissionNotFound ?? 'Submission not found')),
          );
          return;
        }

        // Check if payment is already completed FIRST
        try {
          final submissionDoc = await _firestore
              .collection('ad_submissions')
              .doc(submissionId)
              .get();

          if (!mounted) return;

          if (!submissionDoc.exists) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(l10n.submissionNotFound ?? 'Submission not found')),
            );
            return;
          }

          final submissionData = submissionDoc.data();
          final paidAt = submissionData?['paidAt'];

          // If paidAt exists, payment has already been completed
          if (paidAt != null) {
            showDialog(
              context: context,
              builder: (context) {
                final textColor =
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black;
                return CupertinoAlertDialog(
                  title: Text(
                    l10n.paymentCompleted ?? 'Payment Completed',
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 18.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  content: Text(
                    l10n.adPaymentAlreadyCompleted ??
                        'This ad has already been paid for and is active.',
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16.0,
                    ),
                  ),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n.ok,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
            return; // IMPORTANT: Return here to prevent navigation
          }

          // Only proceed to payment if paidAt doesn't exist (not yet paid)
          final adType = notification.adType;
          final duration = notification.duration;
          final price = notification.price;
          final imageUrl = notification.imageUrl;
          final shopName = notification.shopName;
          final paymentLink = notification.paymentLink;

          if (adType != null &&
              duration != null &&
              price != null &&
              imageUrl != null &&
              paymentLink != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DynamicPaymentScreen(
                  submissionId: submissionId,
                  adType: adType,
                  duration: duration,
                  price: price,
                  imageUrl: imageUrl,
                  shopName: shopName ?? 'Your Shop',
                  paymentLink: paymentLink,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(l10n.paymentInfoNotFound ??
                      'Payment information not found')),
            );
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.errorOccurredWithDetails(e.toString())),
            ),
          );
        }
        break;

      case 'product_edit_approved':
        final productId = notification.productId;
        if (productId != null) {
          context.push('/product/$productId');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.productInfoNotFound)),
          );
        }
        break;

      case 'product_edit_rejected':
        final rejectionReason = notification.rejectionReason;
        showDialog(
          context: context,
          builder: (context) {
            final textColor = Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black;
            return CupertinoAlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message ?? l10n.productEditRejectedMessage,
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (rejectionReason != null &&
                      rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.rejectionReason,
                      style: const TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        rejectionReason,
                        style: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 16.0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.done,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
        break;

      case 'campaign':
        final shopId = notification.shopId;
        if (shopId != null) {
          context.push('/seller-panel?shopId=$shopId&tab=0');
        } else {
          context.push('/seller-panel?tab=0');
        }
        break;

      case 'product_review':
        final productId = notification.productId;
        if (productId != null) {
          try {
            final productSnapshot =
                await _firestore.collection('products').doc(productId).get();
            if (!mounted) return;
            if (productSnapshot.exists) {
              final product = Product.fromDocument(productSnapshot);
              context.push('/product_detail/${product.id}');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.productInfoNotFound)),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.errorOccurredWithDetails(e.toString())),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.productInfoNotFound)),
          );
        }
        break;

      case 'product_out_of_stock_seller_panel':
        final shopId = notification.shopId;
        if (shopId != null) {
          context.push('/seller-panel?tab=2&shopId=$shopId');
        }
        break;

      case 'shop_invitation':
        showDialog(
          context: context,
          builder: (context) {
            final inviterName = notification.inviterName ?? '';
            final shopName = notification.shopName ?? '';
            final textColor = Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black;
            return CupertinoAlertDialog(
              content: Text(
                l10n.invitationMessage(inviterName, shopName),
                style: const TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _handleInvitationResponse(notification,
                        accepted: false);
                  },
                  child: Text(
                    l10n.reject,
                    style: TextStyle(
                        color: textColor, fontWeight: FontWeight.bold),
                  ),
                ),
                CupertinoDialogAction(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _handleInvitationResponse(notification,
                        accepted: true);
                  },
                  child: Text(
                    l10n.accept,
                    style: TextStyle(color: Color(0xFF00A86B)),
                  ),
                ),
              ],
            );
          },
        );
        break;

      case 'shipment':
        final productId = notification.productId;
        final transactionId = notification.transactionId;
        if (productId != null && transactionId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShipmentStatusScreen(
                orderId: transactionId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.productInfoNotFound)),
          );
        }
        break;

      case 'shop_approved':
        final shopId = notification.shopId;
        if (shopId != null) {
          context.push('/seller-panel?shopId=$shopId&tab=0');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.shopInfoNotFound)),
          );
        }
        break;

      case 'product_question':
        final productId = notification.productId;
        final isShopProduct = notification.isShopProduct ?? false;
        final shopId = notification.shopId;

        if (productId != null) {
          if (isShopProduct && shopId != null) {
            // ✅ FIX: Replace :shopId with actual shopId value
            context.push('/seller_panel_product_questions/$shopId');
          } else {
            context.push('/user-product-questions');
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.productInfoNotFound)),
          );
        }
        break;

      case 'shop_disapproved':
        final rejectionReason = notification.rejectionReason;
        showDialog(
          context: context,
          builder: (context) {
            final textColor = Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black;
            return CupertinoAlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message ?? l10n.shopDisapprovedMessage,
                    style: const TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (rejectionReason != null &&
                      rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.rejectionReason,
                      style: const TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        rejectionReason,
                        style: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 16.0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.done,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
        break;

      case 'product_review_shop':
        final shopId = notification.shopId;
        if (shopId != null) {
          context.push('/seller_panel_reviews/$shopId');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.shopInfoNotFound)),
          );
        }
        break;

      case 'product_review_user':
        final productId = notification.productId;
        if (productId != null) {
          context.push('/product_detail/$productId');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.productInfoNotFound)),
          );
        }
        break;

      case 'seller_review_shop':
        final shopId = notification.shopId;
        if (shopId != null) {
          context.push('/seller_panel_reviews/$shopId');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.shopInfoNotFound)),
          );
        }
        break;

      case 'seller_review_user':
        final sellerId = notification.sellerId;
        if (sellerId != null) {
          context.push('/seller_reviews/$sellerId');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.sellerInfoNotFound)),
          );
        }
        break;

      case 'product_sold_shop':
        final shopId = notification.shopId;
        if (shopId != null) {
          context.push('/seller-panel?shopId=$shopId&tab=3');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.shopInfoNotFound)),
          );
        }
        break;

      case 'product_sold_user':
        context.push('/my_orders?tab=1');
        break;

      case 'product_out_of_stock':
        final productId = notification.productId;
        if (productId != null) {
          try {
            final productSnapshot =
                await _firestore.collection('products').doc(productId).get();
            if (!mounted) return;
            if (productSnapshot.exists) {
              final product = Product.fromDocument(productSnapshot);
              context.push('/product_detail/${product.id}');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.productInfoNotFound)),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.errorOccurredWithDetails(e.toString())),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.productInfoNotFound)),
          );
        }
        break;

      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final backButtonColor = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.onSurface
        : Colors.black;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: backButtonColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l10n.notifications,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          elevation: 0,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/mobile-notification.png',
                  width: 150,
                  height: 150,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.3)
                      : null,
                  colorBlendMode:
                      Theme.of(context).brightness == Brightness.dark
                          ? BlendMode.srcATop
                          : null,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.noLoggedInForNotifications,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => context.push('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            l10n.login2,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => context.push('/register'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                          ),
                          child: Text(
                            l10n.register,
                            style: GoogleFonts.inter(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
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
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: backButtonColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.notifications,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF00A86B),
        // Show shimmer during initial load for authenticated users
        child: _isInitialLoad
            ? _buildNotificationShimmer(isDarkMode)
            : _notifications.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/mobile-notification.png',
                            width: 140,
                            height: 140,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noNotifications,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                              fontSize: 16,
                              fontFamily: 'Figtree',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _notifications.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _notifications.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final notification = _notifications[index];
                      final docId = notification.id;

                      final messageEn = notification.messageEn ?? '';
                      final messageTr = notification.messageTr ?? '';
                      final messageRu = notification.messageRu ?? '';
                      final deviceLocale = Localizations.localeOf(context);
                      final languageCode = deviceLocale.languageCode;
                      final type = notification.type ?? 'general';

                      String message;
                      if (type == 'campaign') {
                        message = notification.campaignDescription ??
                            (notification.message ?? '');
                      } else if (type == 'boost_expired') {
                        final productName = notification.productName ?? '';
                        final reason = notification.reason ?? '';
                        if (reason == 'admin_archived') {
                          message = l10n.boostExpiredAdminArchived(productName);
                        } else if (reason == 'seller_archived') {
                          message =
                              l10n.boostExpiredSellerArchived(productName);
                        } else {
                          message = l10n.boostExpiredGeneric(productName);
                        }
                      } else if (type == 'shop_approved') {
                        message = l10n.tapToVisitYourShop;
                      } else if (type == 'shop_disapproved') {
                        message = l10n.shopDisapprovedMessage;
                      } else if (type == 'refund_request_approved') {
                        message = l10n.refundRequestApprovedMessage;
                      } else if (type == 'refund_request_rejected') {
                        message = l10n.refundRequestRejectedMessage;
                      } else if (type == 'product_archived_by_admin') {
                        final productName = notification.productName ?? '';
                        final needsUpdate = notification.needsUpdate ?? false;
                        final archiveReason = notification.archiveReason ?? '';
                        final boostExpired = notification.boostExpired ?? false;
                        if (needsUpdate && archiveReason.isNotEmpty) {
                          message = l10n.productArchivedNeedsUpdate(
                              productName, archiveReason);
                        } else {
                          message = l10n.productArchivedSimple(productName);
                        }
                        if (boostExpired) {
                          message += ' ${l10n.productArchivedBoostNote}';
                        }
                      } else {
                        switch (languageCode) {
                          case 'tr':
                            message = messageTr.isNotEmpty
                                ? messageTr
                                : (notification.message ?? '');
                            break;
                          case 'ru':
                            message = messageRu.isNotEmpty
                                ? messageRu
                                : (notification.message ?? '');
                            break;
                          default:
                            message = messageEn.isNotEmpty
                                ? messageEn
                                : (notification.message ?? '');
                        }
                      }

                      final timestamp = notification.timestamp ??
                          Timestamp.fromDate(DateTime.now());

                      IconData notificationIcon;
                      Color iconColor;
                      switch (type) {
                        case 'shop_invitation':
                          notificationIcon = Icons.person_add;
                          iconColor = const Color.fromARGB(255, 182, 91, 0);
                          break;
                        case 'boosted':
                        case 'boost_expired':
                          notificationIcon = Icons.trending_up;
                          iconColor = const Color(0xFF00A86B);
                          break;
                        case 'order_delivered':
                          notificationIcon = Icons.local_shipping;
                          iconColor = const Color(0xFF00A86B);
                          break;
                        case 'product_archived_by_admin':
                          notificationIcon = Icons.archive_rounded;
                          iconColor = Colors.red;
                          break;
                        case 'product_review_shop':
                        case 'product_review_user':
                        case 'seller_review_shop':
                        case 'seller_review_user':
                          notificationIcon = Icons.star;
                          iconColor = const Color(0xFFFFD700);
                          break;
                        case 'shipment':
                          notificationIcon = Icons.local_shipping;
                          iconColor = Color(0xFF00A86B);
                          break;
                        case 'product_question_answered':
                          notificationIcon = Icons.question_answer_rounded;
                          iconColor = const Color(0xFF00A86B);
                          break;
                        case 'shop_approved':
                          notificationIcon = Icons.store;
                          iconColor = Colors.green;
                          break;
                        case 'shop_disapproved':
                          notificationIcon = Icons.store;
                          iconColor = Colors.red;
                          break;
                        case 'product_out_of_stock':
                          notificationIcon = Icons.warning;
                          iconColor = Color(0xFF00A86B);
                          break;
                        case 'ad_approved':
                          notificationIcon = Icons.campaign_rounded;
                          iconColor = const Color(0xFF9F7AEA);
                          break;
                        case 'product_out_of_stock_seller_panel':
                          notificationIcon = Icons.warning;
                          iconColor = Color(0xFF00A86B);
                          break;
                        case 'seller_review':
                          notificationIcon = Icons.rate_review;
                          iconColor = const Color.fromARGB(255, 0, 132, 255);
                          break;
                        case 'campaign':
                          notificationIcon = Icons.campaign;
                          iconColor = const Color(0xFFFF6B6B);
                          break;
                        case 'product_sold_shop':
                        case 'product_sold_user':
                          notificationIcon = Icons.sell;
                          iconColor = const Color(0xFF00A86B);
                          break;
                        case 'product_question':
                          notificationIcon = Icons.help_outline;
                          iconColor = const Color(0xFF2196F3);
                          break;
                        case 'refund_request_approved':
                          notificationIcon = Icons.check_circle;
                          iconColor = Colors.green;
                          break;
                        case 'refund_request_rejected':
                          notificationIcon = Icons.cancel;
                          iconColor = Colors.red;
                          break;
                        default:
                          notificationIcon = Icons.notifications;
                          iconColor = const Color.fromARGB(255, 182, 91, 0);
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4.0, horizontal: 8.0),
                        child: Dismissible(
                          key: Key(docId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Theme.of(context).colorScheme.error,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Icon(
                              Icons.delete,
                              color: Theme.of(context).colorScheme.onError,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog(
                              context: context,
                              builder: (context) {
                                return CupertinoAlertDialog(
                                  content: Text(
                                    l10n.confirmDeleteNotification,
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  actions: [
                                    CupertinoDialogAction(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: Text(
                                        l10n.cancel,
                                        style: TextStyle(
                                          color: Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ),
                                    CupertinoDialogAction(
                                      isDestructiveAction: true,
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: Text(l10n.delete),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          onDismissed: (direction) {
                            _deleteNotification(docId);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              border: Border.all(
                                  color:
                                      const Color.fromARGB(255, 240, 240, 240),
                                  width: 1.0),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: ListTile(
                              leading: Icon(notificationIcon, color: iconColor),
                              title: Text(
                                type == 'campaign'
                                    ? (notification.campaignName ??
                                        _getTitleForType(type, l10n,
                                            notification: notification))
                                    : _getTitleForType(type, l10n,
                                        notification: notification),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    message,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontSize: 14,
                                      fontFamily: 'Figtree',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(timestamp),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontSize: 12,
                                      fontFamily: 'Figtree',
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _handleNotificationTap(notification),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  /// Builds shimmer placeholder for notifications loading state
  Widget _buildNotificationShimmer(bool isDarkMode) {
    final baseColor =
        isDarkMode ? const Color.fromARGB(255, 30, 28, 44) : Colors.grey[300]!;
    final highlightColor =
        isDarkMode ? const Color.fromARGB(255, 45, 42, 65) : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8, // Show 8 placeholder items
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon placeholder
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Content placeholder
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title placeholder
                          Container(
                            height: 14,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Message placeholder line 1
                          Container(
                            height: 12,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Message placeholder line 2
                          Container(
                            height: 12,
                            width: 180,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Timestamp placeholder
                          Container(
                            height: 10,
                            width: 100,
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
              ),
            ),
          );
        },
      ),
    );
  }

  String _getTitleForType(String type, AppLocalizations l10n,
      {NotificationModel? notification}) {
    switch (type) {
      case 'product_sold_shop':
        return l10n.productSold;
      case 'product_sold_user':
        return l10n.productSold;
      case 'shop_invitation':
        return l10n.invitation;
      case 'boosted':
        return l10n.boosted;
      case 'boost_expired':
        return l10n.boostExpired;
      case 'product_archived_by_admin':
        return l10n.productArchivedByAdmin;
      case 'order_delivered':
        return l10n.orderDelivered ?? 'Order Delivered';
      case 'shipment':
        return l10n.shipment;
      case 'shop_approved':
        return l10n.shopApprovedTitle;
      case 'shop_disapproved':
        return l10n.shopDisapprovedTitle;
      case 'ad_approved':
        return l10n.adApproved ?? 'Ad Approved';
      case 'message':
        return l10n.message;
      case 'product_review_shop':
      case 'product_review_user':
        return l10n.productReview;
      case 'seller_review_shop':
      case 'seller_review_user':
        return l10n.sellerReview;
      case 'product_question_answered':
        return l10n.questionAnswered ?? 'Question Answered 💬';
      case 'product_out_of_stock':
        return l10n.productOutOfStock2;
      case 'product_out_of_stock_seller_panel':
        return l10n.productOutOfStockSellerPanel;
      case 'campaign':
        return l10n.campaign;
      case 'product_question':
        return l10n.productQuestion;
      case 'refund_request_approved':
        return l10n.refundApproved;
      case 'refund_request_rejected':
        return l10n.refundRejected;
      default:
        return l10n.notification;
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $hour:$minute';
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../theme.dart';
import '../AGREEMENTS/kisisel_veriler.dart';

class AskToSellerScreen extends StatefulWidget {
  final String productId;
  final String sellerId;
  final bool isShop;

  const AskToSellerScreen({
    Key? key,
    required this.productId,
    required this.sellerId,
    required this.isShop,
  }) : super(key: key);

  @override
  _AskToSellerScreenState createState() => _AskToSellerScreenState();
}

class _AskToSellerScreenState extends State<AskToSellerScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _allowNameVisible = false;
  bool _acceptTerms = false;
  bool _isSubmitting = false;
  int _charCount = 0;

  late final Future<DocumentSnapshot<Map<String, dynamic>>> _sellerFuture;

  @override
  void initState() {
    super.initState();
    _controller.addListener(
        () => setState(() => _charCount = _controller.text.length));
    final baseColl = widget.isShop ? 'shops' : 'users';
    _sellerFuture = FirebaseFirestore.instance
        .collection(baseColl)
        .doc(widget.sellerId)
        .get();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ✅ REMOVED: _getShopMemberIds() - No longer needed, handled by Cloud Function

  /// Creates question notifications via Cloud Function
  Future<void> _createQuestionNotifications({
    required String productId,
    required String productName,
    required String questionText,
    required String askerName,
    required String askerId,
  }) async {
    try {
      print('📧 Calling Cloud Function to create notifications...');

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

      // Call the Cloud Function
      final callable = functions.httpsCallable(
        'createProductQuestionNotification',
      );

      final result = await callable.call({
        'productId': productId,
        'productName': productName,
        'questionText': questionText,
        'askerName': askerName,
        'isShopProduct': widget.isShop,
        'shopId': widget.isShop ? widget.sellerId : null, // ✅ For shop products
        'sellerId':
            !widget.isShop ? widget.sellerId : null, // ✅ For user products
      });

      final data = result.data as Map<String, dynamic>;
      final notificationsSent = data['notificationsSent'] as int? ?? 0;
      final processingTime = data['processingTime'] as int? ?? 0;

      print(
          '✅ Notifications sent to $notificationsSent recipients in ${processingTime}ms');
    } catch (e) {
      print('❌ Error creating question notifications: $e');
      // Don't throw - notifications are non-critical, question was still saved
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final text = _controller.text.trim();

    // Check if user is authenticated first
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseLoginToSubmitQuestion)),
      );
      return;
    }

    // validation
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.askToSellerAcceptTermsError)),
      );
      return;
    }
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.askToSellerEmptyQuestionError)),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // fetch asker name
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final askerName = userDoc.data()?['displayName'] as String? ?? '';

      // fetch seller info for denormalization
      final sellerColl = widget.isShop ? 'shops' : 'users';
      final sellerDoc = await FirebaseFirestore.instance
          .collection(sellerColl)
          .doc(widget.sellerId)
          .get();
      final sellerData = sellerDoc.data() ?? {};

      // Extract seller name and image based on shop or user
      final sellerName = widget.isShop
          ? (sellerData['name'] as String? ?? 'Unknown Shop')
          : (sellerData['displayName'] as String? ?? 'Unknown User');
      final sellerImage = widget.isShop
          ? (sellerData['profileImageUrl'] as String? ?? '')
          : (sellerData['profileImage'] as String? ?? '');

      // fetch product details
      final prodColl = widget.isShop ? 'shop_products' : 'products';
      final prodSnap = await FirebaseFirestore.instance
          .collection(prodColl)
          .doc(widget.productId)
          .get();
      final prodData = prodSnap.data() ?? {};
      final productName = prodData['productName'] as String? ?? '';
      final imageUrls = prodData['imageUrls'] as List<dynamic>? ?? [];
      final productImage =
          imageUrls.isNotEmpty ? imageUrls.first as String : '';
      final productPrice = prodData['price'] as num? ?? 0;
      final productRating =
          (prodData['averageRating'] as num?)?.toDouble() ?? 0.0;

      // prepare question document
      final questionRef = FirebaseFirestore.instance
          .collection(prodColl)
          .doc(widget.productId)
          .collection('product_questions')
          .doc();

      final payload = {
        'questionId': questionRef.id,
        'productId': widget.productId,
        'askerId': user.uid,
        'askerName': askerName,
        'askerNameVisible': _allowNameVisible,
        'questionText': text,
        'timestamp': FieldValue.serverTimestamp(),
        'answered': false,

        // injected product info
        'productName': productName,
        'productImage': productImage,
        'productPrice': productPrice,
        'productRating': productRating,
        'sellerId': widget.sellerId,

        // ADDED: injected seller info for denormalization
        'sellerName': sellerName,
        'sellerImage': sellerImage,
      };

      // save question
      await questionRef.set(payload);

      // ✅ Create notifications via Cloud Function (non-blocking)
      _createQuestionNotifications(
        productId: widget.productId,
        productName: productName,
        questionText: text,
        askerName: _allowNameVisible ? askerName : 'Anonymous',
        askerId: user.uid,
      );

      // close screen immediately (don't wait for notifications)
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.askToSellerSubmitError}: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final linkColor = Colors.blue;
    final bannerColor = Colors.orange.withOpacity(0.1);
    final jade = Theme.of(context).extension<CustomColors>()?.jadeColor ??
        theme.colorScheme.secondary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.askToSellerTitle),
        elevation: 3,
        shadowColor: Colors.black.withOpacity(0.25),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _sellerFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists)
            return Center(child: Text(l10n.askToSellerNoSellerError));

          final seller = snap.data!.data()!;
          final name = widget.isShop
              ? (seller['name'] as String? ?? l10n.anonymous)
              : (seller['displayName'] as String? ?? l10n.anonymous);
          final imgUrl = widget.isShop
              ? seller['profileImageUrl'] as String?
              : seller['profileImage'] as String?;
          final rating = (seller['averageRating'] as num?)?.toDouble() ?? 0.0;

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Seller info
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.orange.withOpacity(0.2),
                        backgroundImage:
                            imgUrl != null ? NetworkImage(imgUrl) : null,
                        child: imgUrl == null
                            ? Icon(widget.isShop ? Icons.store : Icons.person)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(name, style: theme.textTheme.titleMedium),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: jade,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          rating.toStringAsFixed(1),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  // Info banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bannerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium,
                        children: [
                          TextSpan(text: l10n.askToSellerInfoStart),
                          TextSpan(
                            text: l10n.askToSellerInfoOrdersLink,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: linkColor, fontWeight: FontWeight.bold),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => context.push('/my_orders'),
                          ),
                          TextSpan(text: l10n.askToSellerInfoEnd),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  // Question input label + criteria link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.askToSellerQuestionLabel,
                          style: theme.textTheme.titleMedium),
                    ],
                  ),

                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    maxLines: 5,
                    maxLength: 150,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4)),
                      hintText: l10n.askToSellerQuestionHint,
                      counterText: '$_charCount/150',
                      filled: true,
                      fillColor: surface,
                    ),
                  ),

                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _allowNameVisible,
                    onChanged: (v) => setState(() => _allowNameVisible = v!),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(l10n.askToSellerNameVisibility),
                  ),

                  CheckboxListTile(
                    value: _acceptTerms,
                    onChanged: (v) => setState(() => _acceptTerms = v!),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text.rich(
                      TextSpan(
                        text: l10n.askToSellerAcceptTermsPrefix,
                        style: theme.textTheme.bodyMedium,
                        children: [
                          TextSpan(
                            text: l10n.askToSellerAcceptTermsLink,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: linkColor,
                                decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const PersonalDataScreen(),
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
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(l10n.askToSellerSend,
                  style:
                      theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
        ),
      ),
    );
  }
}

// lib/widgets/productdetail/product_detail_actions_row.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/favorite_product_provider.dart';
import '../../auth_service.dart';
import '../login_modal.dart';
import 'dart:async';
import '../../services/share_service.dart';

class RotatingCountText extends StatefulWidget {
  final int cartCount;
  final int favoriteCount;
  final int purchaseCount;
  final AppLocalizations l10n;

  /// How long each message stays fully visible before animating out
  final Duration displayDuration;

  const RotatingCountText({
    Key? key,
    required this.cartCount,
    required this.favoriteCount,
    required this.purchaseCount,
    required this.l10n,
    this.displayDuration = const Duration(seconds: 2),
  }) : super(key: key);

  @override
  _RotatingCountTextState createState() => _RotatingCountTextState();
}

class _RotatingCountTextState extends State<RotatingCountText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _oldTextSlide;
  late final Animation<Offset> _newTextSlide;
  Timer? _rotationTimer;

  /// current index into our activeMessages list
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _oldTextSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _newTextSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final msgs = _activeMessages;
        if (msgs.isNotEmpty) {
          setState(() {
            // advance safely, modulo the *current* length
            _currentIndex = (_currentIndex + 1) % msgs.length;
          });
        } else {
          setState(() {
            _currentIndex = 0;
          });
        }
        _controller.reset();
        _scheduleNextRotation();
       
      }
    });

    _scheduleNextRotation(); 
  }

   void _scheduleNextRotation() {
    _rotationTimer?.cancel();  // ✅ Cancel any existing timer
    if (_activeMessages.length > 1) {
      _rotationTimer = Timer(widget.displayDuration, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<_Msg> get _activeMessages {
    final msgs = <_Msg>[];
    if (widget.cartCount > 0) {
      msgs.add(_Msg(
        text: widget.l10n.cartCount2(widget.cartCount),
        color: Colors.orange,
      ));
    }
    if (widget.favoriteCount > 0) {
      msgs.add(_Msg(
        text: widget.l10n.favoriteCount2(widget.favoriteCount),
        color: Colors.pink,
      ));
    }
    if (widget.purchaseCount > 0) {
      msgs.add(_Msg(
        text: widget.l10n.purchaseCount2(widget.purchaseCount),
        color: Colors.blue,
      ));
    }
    return msgs;
  }

  @override
  Widget build(BuildContext context) {
    final messages = _activeMessages;

    // 1) none → hide
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }

    // 2) exactly one → static
    if (messages.length == 1) {
      return SizedBox(
        height: 16,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildText(context, messages[0].text, messages[0].color),
        ),
      );
    }

    // 3+) two or more → animate between safe indices
    final int safeIndex = _currentIndex % messages.length;
    final oldMsg = messages[safeIndex];
    final newMsg = messages[(safeIndex + 1) % messages.length];

    return SizedBox(
      height: 16,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            SlideTransition(
              position: _oldTextSlide,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildText(context, oldMsg.text, oldMsg.color),
              ),
            ),
            SlideTransition(
              position: _newTextSlide,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildText(context, newMsg.text, newMsg.color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, String text, Color color) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodySmall!
          .copyWith(color: color, fontWeight: FontWeight.w700),
    );
  }
}

/// Simple pair of text+color
class _Msg {
  final String text;
  final Color color;
  _Msg({required this.text, required this.color});
}

class ProductDetailActionsRow extends StatefulWidget {
  final Product product;

  const ProductDetailActionsRow({Key? key, required this.product})
      : super(key: key);

  @override
  _ProductDetailActionsRowState createState() =>
      _ProductDetailActionsRowState();
}

class _ProductDetailActionsRowState extends State<ProductDetailActionsRow> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final favoriteProvider = Provider.of<FavoriteProvider>(context);
    // Use the global union check.
    
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final txtColor = isDarkMode ? Colors.white : Colors.black;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color:
            isDarkMode ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: star rating and detail chips.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Star rating with numeric value and quantity.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStarRating(context, widget.product.averageRating),
                    const SizedBox(width: 3),
                    Text(
                      widget.product.averageRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    RotatingCountText(
                      cartCount: widget.product.cartCount,
                      favoriteCount: widget.product.favoritesCount,
                      purchaseCount: widget.product.purchaseCount,
                      l10n: l10n,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Detail chips row.
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    // Only show brand chip if brandModel exists and is not empty
                    if (widget.product.brandModel != null &&
                        widget.product.brandModel!.isNotEmpty)
                      _buildDetailChip(
                        context,
                        title: l10n.brand,
                        value: widget.product.brandModel!,
                      ),
                    _buildDetailChip(
                      context,
                      title: l10n.deliveryOption,
                      value: widget.product.deliveryOption ?? '-',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right side: share and favorite icons.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  FontAwesomeIcons.share,
                  color: Colors.grey,
                ),
                tooltip: 'Share',
                onPressed: _shareProduct, // ✅ Fixed: Direct function call
              ),
            ValueListenableBuilder<Set<String>>(
  valueListenable: favoriteProvider.globalFavoriteIdsNotifier,
  builder: (context, globalFavoriteIds, child) {
    final isFavorite = globalFavoriteIds.contains(widget.product.id);
    
    return IconButton(
      icon: Icon(
        isFavorite
            ? FontAwesomeIcons.solidHeart
            : FontAwesomeIcons.heart,
        color: isFavorite ? Colors.red : Colors.grey,
      ),
      tooltip: 'Favorite',
      onPressed: () async {
  final authService =
      Provider.of<AuthService>(context, listen: false);

  // If not authenticated → show login prompt and bail out
  if (authService.currentUser == null) {
    await showCupertinoModalPopup(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          LoginPromptModal(authService: authService),
    );
    return;
  }

  // 1) If already favorited, handle removal...
  if (favoriteProvider.isGloballyFavorited(widget.product.id)) {
    final inBasket = await favoriteProvider
        .isFavoritedInBasket(widget.product.id);
    if (inBasket) {
      final basketName = await favoriteProvider
              .getBasketNameForProduct(widget.product.id) ??
          'Basket';
      final confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.removeFromBasketTitle(basketName)),
          content:
              Text(l10n.removeFromBasketContent(basketName)),
          actions: [
            CupertinoDialogAction(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Figtree',
                  color:
                      isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
            CupertinoDialogAction(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: Text(
                l10n.confirm,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Figtree',
                  color:
                      isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    // remove from favorites
    await favoriteProvider
        .removeGloballyFromFavorites(widget.product.id);
    return;
  }

  // ✅ MODIFIED: Direct add to favorites without selector
  await favoriteProvider.addToFavorites(
    widget.product.id,
    quantity: 1,
    selectedColor: null, // No color selection
    selectedColorImage: widget.product.imageUrls.isNotEmpty 
        ? widget.product.imageUrls.first 
        : null,
    additionalAttributes: {}, // No additional attributes
    context: context,
  );
},

              );
            },
          ),
            ],
          ),
        ],
      ),
    );
  }

  /// Show share options modal
  Future<void> _shareProduct() async {
    await ShareService.shareProduct(
      product: widget.product,
      context: context,
    );
  } 

  /// Builds a compact star rating row.
  Widget _buildStarRating(BuildContext context, double rating) {
    final int fullStars = rating.floor();
    final bool hasHalfStar = (rating - fullStars) >= 0.5;
    final int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    List<Widget> stars = [];

    for (int i = 0; i < fullStars; i++) {
      stars.add(const Icon(
        FontAwesomeIcons.solidStar,
        size: 13,
        color: Colors.amber,
      ));
    }
    if (hasHalfStar) {
      stars.add(const Icon(
        FontAwesomeIcons.starHalfStroke,
        size: 13,
        color: Colors.amber,
      ));
    }
    for (int i = 0; i < emptyStars; i++) {
      stars.add(const Icon(
        FontAwesomeIcons.star,
        size: 13,
        color: Colors.grey,
      ));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: stars
          .map((star) => Padding(
                padding: const EdgeInsets.only(right: 0.5),
                child: star,
              ))
          .toList(),
    );
  }

  /// Builds a detail chip.
  Widget _buildDetailChip(BuildContext context,
      {required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 9,
              color: Colors.orange[800],
              height: 1.0,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[700],
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

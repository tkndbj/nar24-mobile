// lib/widgets/favorite_basket_widget.dart - Basket Management Widget

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/favorite_product_provider.dart';
import '../generated/l10n/app_localizations.dart';

/// Extracted basket management widget for cleaner separation of concerns
class FavoriteBasketWidget extends StatelessWidget {
  final Function()? onBasketChanged;

  const FavoriteBasketWidget({
    Key? key,
    this.onBasketChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('favorite_baskets')
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> baskets = [];
        if (snapshot.hasData) {
          baskets = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            return data;
          }).toList();
        }

        final favoriteProvider =
            Provider.of<FavoriteProvider>(context, listen: false);
        String? selectedBasketId = favoriteProvider.selectedBasketId;

        return Container(
          padding: const EdgeInsets.only(left: 10, top: 8, bottom: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Basket chips
                ...baskets.map((basket) => _buildBasketChip(
                      context,
                      basket,
                      isSelected: basket['id'] == selectedBasketId,
                      favoriteProvider: favoriteProvider,
                      l10n: l10n,
                    )),
                // Create basket chip
                _buildCreateBasketChip(
                  context,
                  baskets,
                  favoriteProvider,
                  l10n,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBasketChip(
    BuildContext context,
    Map<String, dynamic> basket, {
    required bool isSelected,
    required FavoriteProvider favoriteProvider,
    required AppLocalizations l10n,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () {
          // Toggle basket selection
          if (isSelected) {
            favoriteProvider.setSelectedBasket(null);
          } else {
            favoriteProvider.setSelectedBasket(basket['id']);
          }

          // Notify parent to reload if needed
          onBasketChanged?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.orange
                : (isDark ? const Color.fromARGB(255, 37, 35, 54) : Colors.grey[600]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                basket['name'],
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showDeleteBasketDialog(
                  context,
                  basket['id'],
                  favoriteProvider,
                  l10n,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateBasketChip(
    BuildContext context,
    List<Map<String, dynamic>> baskets,
    FavoriteProvider favoriteProvider,
    AppLocalizations l10n,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () async {
          if (baskets.length >= 10) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.maxBasketsReached)),
            );
            return;
          }

          try {
            String? basketName = await _showCreateBasketDialog(context, l10n);
            if (basketName != null && basketName.isNotEmpty) {
              await favoriteProvider.createFavoriteBasket(
                basketName,
                context: context,
              );
            }
          } catch (e) {
            debugPrint('Error creating basket: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error creating basket: $e')),
              );
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[400],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.createBasket,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.add, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showCreateBasketDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    TextEditingController controller = TextEditingController();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final actionTextStyle = TextStyle(
      color: isDark ? Colors.white : null,
    );

    return showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 600;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isTablet ? 500 : double.infinity,
              ),
              child: CupertinoActionSheet(
                title: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.createBasket,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoTextField(
                        controller: controller,
                        placeholder: l10n.enterBasketName,
                        autofocus: true,
                        cursorColor: isDark ? Colors.white : null,
                        style: TextStyle(
                          fontSize: 16,
                          color: brightness == Brightness.light
                              ? CupertinoColors.black
                              : CupertinoColors.white,
                        ),
                        decoration: BoxDecoration(
                          color: brightness == Brightness.light
                              ? CupertinoColors.systemGrey6
                              : CupertinoColors.systemGrey5.darkColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () {
                      final name = controller.text.trim();
                      Navigator.pop(context, name.isNotEmpty ? name : null);
                    },
                    isDefaultAction: true,
                    child: Text(l10n.create, style: actionTextStyle),
                  ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(l10n.cancel, style: actionTextStyle),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteBasketDialog(
    BuildContext context,
    String basketId,
    FavoriteProvider favoriteProvider,
    AppLocalizations l10n,
  ) async {
    final brightness = Theme.of(context).brightness;
    final actionTextStyle = TextStyle(
      color: brightness == Brightness.light ? Colors.black : Colors.white,
    );

    bool confirm = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: Text(l10n.doYouWantToDeleteBasket, style: actionTextStyle),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel, style: actionTextStyle),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.confirm, style: actionTextStyle),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirm) {
      try {
        await favoriteProvider.deleteFavoriteBasket(
          basketId,
          context: context,
        );
      } catch (e) {
        debugPrint('Error deleting basket: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting basket: $e')),
          );
        }
      }
    }
  }
}

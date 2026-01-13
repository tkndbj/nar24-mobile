import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/special_filter_provider_teras.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../screens/market_screen.dart';
import '../login_modal.dart';
import '../../auth_service.dart';

class TerasFilterSortRow extends StatelessWidget {
  final ScrollController? scrollController;

  const TerasFilterSortRow({Key? key, this.scrollController}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<SpecialFilterProviderTeras>(
      builder: (ctx, specialProv, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: SizedBox(
            height: 30,
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 16.0),
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemCount: 2, // Categories and List Product
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  // Categories button
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 0.75,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15.5),
                          ),
                          child: TextButton(
                            onPressed: () {
                              // Navigate to CategoriesTerasScreen without re-rendering app bar/bottom nav
                              context
                                  .findAncestorStateOfType<MarketScreenState>()
                                  ?.navigateToCategoriesTeras();
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                                horizontal: 8.0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.category,
                                  size: 16,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.categories,
                                  style: TextStyle(
                                    fontFamily: 'Figtree',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                } else if (i == 1) {
                  // List Product button
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 0.75,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15.5),
                          ),
                          child: TextButton(
                            onPressed: () async {
                              final userId =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (userId == null) {
                                showCupertinoModalPopup(
                                  context: context,
                                  builder: (context) => LoginPromptModal(
                                    authService: AuthService(),
                                  ),
                                );
                                return;
                              }
                              final userDoc = await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(userId)
                                  .get();
                              final sellerInfo = userDoc.data()?['sellerInfo']
                                  as Map<String, dynamic>?;
                              if (sellerInfo != null) {
                                context.push('/list_product_screen');
                              } else {
                                context.push('/seller_info',
                                    extra: {'redirectToListProduct': true});
                              }
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                                horizontal: 8.0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.list,
                                  size: 16,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.sellOnVitrin,
                                  style: TextStyle(
                                    fontFamily: 'Figtree',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
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
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );
  }
}

// lib/widgets/dynamicscreens/market_app_bar.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/market_provider.dart';
import 'package:go_router/go_router.dart';
import '../../route_observer.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/search_provider.dart';

class MarketAppBar extends StatefulWidget implements PreferredSizeWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onTakePhoto;
  final VoidCallback onSelectFromAlbum;
  final Future<void> Function() onSubmitSearch;
  final VoidCallback? onBackPressed;
  final bool isSearching;
  final ValueChanged<bool> onSearchStateChanged;

  const MarketAppBar({
    Key? key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onTakePhoto,
    required this.onSelectFromAlbum,
    required this.onSubmitSearch,
    required this.isSearching,
    required this.onSearchStateChanged,
    this.onBackPressed,
  }) : super(key: key);

  @override
  State<MarketAppBar> createState() => _MarketAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MarketAppBarState extends State<MarketAppBar>
    with SingleTickerProviderStateMixin, RouteAware {
  late MarketProvider _marketProv;
  late AppLocalizations _l10n;

  @override
  void initState() {
    super.initState();
    // Keep it simple - no provider setup here
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
    _marketProv = Provider.of<MarketProvider>(context, listen: false);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      color: isDark ? const Color(0xFF1C1A29) : Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: Icon(
                  FeatherIcons.arrowLeft,
                  color: isDark ? Colors.white : Colors.black,
                ),
                onPressed: () async {
                  if (widget.isSearching) {
                    // Exit search mode
                    widget.onSearchStateChanged(false);
                    widget.searchController.clear();
                    widget.searchFocusNode.unfocus();
                  } else {
                    // Handle back navigation
                    if (widget.onBackPressed != null) {
                      widget.onBackPressed!();
                    } else {
                      final didPop = await Navigator.of(context).maybePop();
                      if (!didPop) {
                        GoRouter.of(context).go('/');
                      }
                    }
                  }
                },
              ),

              // Search bar
              Expanded(
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: EdgeInsets.only(
                      left: widget.isSearching ? 0 : 8,
                      right: widget.isSearching ? 8 : 4,
                    ),
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      border: Border.all(
                        color: widget.isSearching
                            ? (isDark ? Colors.white : Colors.grey)
                            : Colors.grey.withAlpha(128),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      readOnly: !widget.isSearching,
                      autofocus: false, // Let parent handle focus
                      controller: widget.searchController,
                      focusNode: widget.searchFocusNode,
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.searchProducts,
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white.withAlpha(179)
                              : Colors.black.withAlpha(179),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 32,
                          maxWidth: 32,
                          minHeight: 32,
                          maxHeight: 32,
                        ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 32,
                          maxWidth: 32,
                          minHeight: 32,
                          maxHeight: 32,
                        ),
                        suffixIcon: widget.isSearching
                            ? IconButton(
                                icon: const Icon(
                                  FeatherIcons.search,
                                  color: Colors.orange,
                                ),
                                onPressed: () {
                                  widget.onSubmitSearch();
                                },
                              )
                            : GestureDetector(
                                onTap: () {
                                  widget.onSearchStateChanged(true);
                                  // Focus happens in parent screen
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (widget
                                        .searchFocusNode.canRequestFocus) {
                                      widget.searchFocusNode.requestFocus();
                                    }
                                  });
                                },
                                behavior: HitTestBehavior.translucent,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(
                                    FeatherIcons.search,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                      ),

                      // ADD THIS - The missing onChanged callback
                      onChanged: widget.isSearching
                          ? (value) {
                              Provider.of<SearchProvider>(context,
                                      listen: false)
                                  .updateTerm(value, l10n: l10n);
                            }
                          : null,

                      onSubmitted: (_) {
                        widget.onSubmitSearch();
                      },
                      onTap: () {
                        if (!widget.isSearching) {
                          widget.onSearchStateChanged(true);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (widget.searchFocusNode.canRequestFocus) {
                              widget.searchFocusNode.requestFocus();
                            }
                          });
                        }
                      },
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

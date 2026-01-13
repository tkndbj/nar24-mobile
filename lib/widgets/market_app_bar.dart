import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../generated/l10n/app_localizations.dart';
import '../providers/search_provider.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../providers/badge_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

class MarketAppBar extends StatefulWidget implements PreferredSizeWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  final Future<void> Function() onSubmitSearch;
  final ValueListenable<Color> backgroundColorNotifier;
  final bool useWhiteColors;
  final bool isDefaultView;
  final bool isSearching;
  final ValueChanged<bool> onSearchStateChanged;

  const MarketAppBar({
    Key? key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSubmitSearch,
    required this.backgroundColorNotifier,
    this.useWhiteColors = false,
    this.isDefaultView = false,
    required this.isSearching,
    required this.onSearchStateChanged,
  }) : super(key: key);

  @override
  State<MarketAppBar> createState() => _MarketAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MarketAppBarState extends State<MarketAppBar> {
  // OPTIMIZATION 1: Cache localization
  AppLocalizations? _l10n;

  // OPTIMIZATION 2: Cache theme values
  bool? _isDark;
  ThemeData? _theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
    _theme = Theme.of(context);
    _isDark = _theme!.brightness == Brightness.dark;
  }

  void _handleSearchStateChange(bool searching) {
    debugPrint('🔍 MarketAppBar: Search state changing to: $searching');

    // ✅ FIX: Don't mutate backgroundColorNotifier here.
    // Let the parent (MarketScreen) handle color changes via onSearchStateChanged callback.
    // This prevents race conditions where both parent and child modify the same notifier.

    if (searching) {
      widget.onSearchStateChanged(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.searchFocusNode.canRequestFocus) {
          widget.searchFocusNode.requestFocus();
        }
      });
    } else {
      widget.onSearchStateChanged(false);
      _clearSearchState();
    }
  }

  void _clearSearchState() {
    debugPrint('🧹 MarketAppBar: Clearing search state');
    widget.searchController.clear();
    widget.searchFocusNode.unfocus();
  }

  bool _isLightColor(Color color) {
  // Calculate relative luminance (perceived brightness)
  // Values closer to 1.0 are lighter, closer to 0.0 are darker
  final luminance = color.computeLuminance();
  return luminance > 0.7; // Threshold: 0.7 means quite light
}

 @override
Widget build(BuildContext context) {
  final l10n = _l10n!;
  final isDark = _isDark!;

  return RepaintBoundary(
    child: ValueListenableBuilder<Color>(
      valueListenable: widget.backgroundColorNotifier,
      builder: (context, bgColor, _) {
        // ✅ ADD: Check if background is light
        final isLightBg = _isLightColor(bgColor);
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          color: bgColor,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  if (widget.isSearching)
                    IconButton(
                      icon: Icon(
                        FeatherIcons.arrowLeft,
                        // ✅ UPDATED: Use gray for back arrow when light bg
                        color: isLightBg 
                            ? Colors.grey.shade600 
                            : (isDark ? Colors.white : Colors.black),
                      ),
                      onPressed: () {
                        debugPrint('🔙 MarketAppBar: Back button pressed');
                        _handleSearchStateChange(false);
                      },
                    ),

                  Expanded(child: _buildSearchBar(l10n, isDark, isLightBg)),

                  if (!widget.isSearching) _buildIconRow(isDark),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

  // OPTIMIZATION 4: Extract search bar building
  Widget _buildSearchBar(AppLocalizations l10n, bool isDark, bool isLightBg) {
   
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: EdgeInsets.only(
        left: widget.isSearching ? 0 : 8,
        right: widget.isSearching ? 8 : 4,
      ),
      height: 40,
      decoration: BoxDecoration(
        color: widget.isDefaultView
            ? Colors.white.withAlpha(120)
            : Colors.white.withAlpha(25),
       border: Border.all(
  color: widget.isSearching
      ? (isDark ? Colors.white : Colors.grey)
      : (isLightBg
          ? Colors.grey.shade400  // ✅ Light bg check FIRST
          : (widget.isDefaultView
              ? Colors.white.withAlpha(120)
              : (widget.useWhiteColors
                  ? Colors.white
                  : Colors.grey.withAlpha(128)))),
),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        readOnly: !widget.isSearching,
        autofocus: false,
        controller: widget.searchController,
        focusNode: widget.searchFocusNode,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: _buildInputDecoration(l10n, isDark),
        onChanged: widget.isSearching ? _handleSearchChange : null,
        onSubmitted: (_) {
          debugPrint('🔍 MarketAppBar: Search submitted');
          widget.onSubmitSearch();
        },
        onTap: () {
          if (!widget.isSearching) {
            debugPrint('🔍 MarketAppBar: Search field tapped (onTap)');
            _handleSearchStateChange(true);
          }
        },
      ),
    );
  }

  // OPTIMIZATION 5: Extract input decoration building
  InputDecoration _buildInputDecoration(AppLocalizations l10n, bool isDark) {
    return InputDecoration(
      hintText: l10n.searchProducts,
      hintStyle: _theme!.textTheme.bodySmall!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: widget.isDefaultView
            ? const Color.fromARGB(255, 63, 63, 63)
            : (widget.useWhiteColors
                ? Colors.white.withAlpha(179)
                : (isDark
                    ? Colors.white.withAlpha(179)
                    : Colors.black.withAlpha(179))),
      ),
      border: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              icon: const Icon(FeatherIcons.search, color: Colors.orange),
              onPressed: () {
                debugPrint('🔍 MarketAppBar: Search button pressed');
                widget.onSubmitSearch();
              },
            )
          : GestureDetector(
              onTap: () {
                debugPrint('🔍 MarketAppBar: Search field tapped (suffix)');
                _handleSearchStateChange(true);
              },
              behavior: HitTestBehavior.translucent,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(FeatherIcons.search, color: Colors.orange),
              ),
            ),
    );
  }

  // OPTIMIZATION 6: Extract search change handling
  void _handleSearchChange(String value) {
    try {
      Provider.of<SearchProvider>(context, listen: false)
          .updateTerm(value, l10n: _l10n!);
    } catch (e) {
      debugPrint('Error updating search term: $e');
    }
  }

  // OPTIMIZATION 7: Extract icon row building
  Widget _buildIconRow(bool isDark) {
    return RepaintBoundary(
      child: Row(
        children: [
          _buildNotificationIcon(isDark),
        ],
      ),
    );
  }

  // OPTIMIZATION 8: Extract notification icon building
 Widget _buildNotificationIcon(bool isDark) {
  // Get current background color to check if it's light
  final bgColor = widget.backgroundColorNotifier.value;
  final isLightBg = _isLightColor(bgColor);

  return Consumer<BadgeProvider>(
    builder: (context, badgeProv, _) {
      return ValueListenableBuilder<int>(
        valueListenable: badgeProv.unreadNotificationsCount,
        builder: (context, count, _) {
          final display = count > 10 ? '+10' : count.toString();
          return RepaintBoundary(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(
                    FeatherIcons.bell,
                    // ✅ UPDATED: Use gray icon when background is light/white
                    color: widget.useWhiteColors
                        ? (isLightBg ? Colors.grey.shade600 : Colors.white.withAlpha(179))
                        : (isDark 
                            ? Colors.white 
                            : (isLightBg ? Colors.grey.shade600 : Colors.black)),
                  ),
                  onPressed: () => context.push('/notifications'),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00A86B),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        display,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
}

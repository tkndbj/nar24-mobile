// lib/widgets/shop/shop_search_bar.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import '../../services/algolia_service_manager.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class ShopSearchBar extends StatefulWidget {
  final Function(List<DocumentSnapshot>?, bool) onSearchResultsChanged;
  final Future<void> Function()? onSearchCleared;

  const ShopSearchBar({
    Key? key,
    required this.onSearchResultsChanged,
    this.onSearchCleared,
  }) : super(key: key);

  @override
  ShopSearchBarState createState() => ShopSearchBarState();
}

class ShopSearchBarState extends State<ShopSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final _querySubject = BehaviorSubject<String>();
  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier<bool>(false);

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // Debounced search with 300ms delay
    _querySubject
        .debounceTime(const Duration(milliseconds: 300))
        .listen((query) {
      if (query.isEmpty) {
        _clearSearch();
      } else {
        _performSearch(query);
      }
    });

    // Listen to focus changes
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && mounted) {
        setState(() {});
      }
    });

    // Listen to text changes for immediate UI feedback
    _searchController.addListener(() {
      if (_searchController.text.trim().isNotEmpty &&
          !_isSearchingNotifier.value) {
        _isSearchingNotifier.value = true;
      } else if (_searchController.text.trim().isEmpty &&
          _isSearchingNotifier.value) {
        _isSearchingNotifier.value = false;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _querySubject.close();
    _isSearchingNotifier.dispose();
    super.dispose();
  }

  void _clearSearch() {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _errorMessage = null;
    });

    _isSearchingNotifier.value = false;

    // ✅ ONLY call onSearchCleared - it handles everything
    widget.onSearchCleared?.call();
  }

  void clearSearchAndUnfocus() {
    _searchController.clear();
    _focusNode.unfocus();
    _clearSearch();
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Notify parent that loading started
    widget.onSearchResultsChanged(null, true);

    try {
      final l10n = AppLocalizations.of(context);
      final languageCode = l10n.localeName ?? 'en';

      // Search Algolia
      final algoliaResults = await AlgoliaServiceManager.instance.shopsService
          .searchShops(
            query: query,
            hitsPerPage: 50,
            languageCode: languageCode,
          )
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      // Bail out early if user has changed/cleared search
      if (_searchController.text.trim() != query) {
        return;
      }

      // Extract shop IDs from Algolia results
      final shopIds = algoliaResults
          .map((hit) =>
              hit['objectID']?.toString().replaceAll('shops_', '') ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (shopIds.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        widget.onSearchResultsChanged([], false);
        return;
      }

      // Fetch actual Firestore documents in batches (Firestore 'in' query limit is 10)
      final List<DocumentSnapshot> shopDocs = [];
      const batchSize = 10;

      for (int i = 0; i < shopIds.length; i += batchSize) {
        final batch = shopIds.skip(i).take(batchSize).toList();

        final querySnapshot = await FirebaseFirestore.instance
            .collection('shops')
            .where(FieldPath.documentId, whereIn: batch)
            .where('isActive', isEqualTo: true) // Only fetch active shops
            .get()
            .timeout(const Duration(seconds: 5));

        shopDocs.addAll(querySnapshot.docs);
      }

      if (!mounted) return;

      // Sort results to match Algolia ranking
      shopDocs.sort((a, b) {
        final indexA = shopIds.indexOf(a.id);
        final indexB = shopIds.indexOf(b.id);
        return indexA.compareTo(indexB);
      });

      if (!mounted) return;

      // Check if user has changed/cleared search - don't update with stale results
      if (_searchController.text.trim() != query) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      // Notify parent with results
      widget.onSearchResultsChanged(shopDocs, false);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = AppLocalizations.of(context).searchGeneralError ??
            'Search error occurred';
      });

      // Show error but keep showing all shops
      widget.onSearchResultsChanged(null, false);

      if (kDebugMode) {
        debugPrint('Shop search error: $e');
      }

      // Show error snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            action: SnackBarAction(
              label: AppLocalizations.of(context).retry ?? 'Retry',
              onPressed: () {
                final query = _searchController.text.trim();
                if (query.isNotEmpty) {
                  _performSearch(query);
                }
              },
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red.shade700
                : Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withOpacity(0.2)
              : Colors.white.withOpacity(0.8),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            focusNode: _focusNode,
            controller: _searchController,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              prefixIcon: Container(
                margin: const EdgeInsets.all(8),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isSearchingNotifier,
                  builder: (context, isSearching, _) {
                    if (_isLoading) {
                      return SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? Colors.tealAccent : Colors.teal,
                          ),
                        ),
                      );
                    }
                    return Icon(
                      Icons.search_rounded,
                      size: 18,
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    );
                  },
                ),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: clearSearchAndUnfocus,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade500,
                        ),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.tune_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                    ),
              hintText: l10n.searchShops ?? 'Search shops...',
              hintStyle: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2D3A) : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.tealAccent : Colors.teal,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (value) {
              setState(() {}); // Update to show/hide clear button
              _querySubject.add(value.trim());
            },
          ),
        ),
      ),
    );
  }
}

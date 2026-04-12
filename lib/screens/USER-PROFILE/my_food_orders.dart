import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/myproducts/food_orders_tab.dart';
import 'package:go_router/go_router.dart';

class MyFoodOrdersScreen extends StatefulWidget {
  const MyFoodOrdersScreen({Key? key}) : super(key: key);

  @override
  _MyFoodOrdersScreenState createState() => _MyFoodOrdersScreenState();
}

class _MyFoodOrdersScreenState extends State<MyFoodOrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _currentSearchQuery = '';
  Timer? _searchDebounce;

  final GlobalKey<FoodOrdersTabState> _foodTabKey = GlobalKey();
  bool _hasOrders = false;

  bool get _isAuthenticated => FirebaseAuth.instance.currentUser != null;
  bool get _showSearchBar => _isAuthenticated && _hasOrders;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChange);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _onSearchFocusChange() {
    if (!_searchFocusNode.hasFocus) {
      FocusScope.of(context).unfocus();
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase().trim();
      if (_currentSearchQuery != query) {
        setState(() {
          _currentSearchQuery = query;
        });
        _foodTabKey.currentState?.applySearch(_currentSearchQuery);
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _currentSearchQuery = '';
    });
    _foodTabKey.currentState?.applySearch('');
  }

  void _dismissKeyboard() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Widget _buildSearchBox() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
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
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            prefixIcon: Container(
              margin: const EdgeInsets.all(8),
              child: Icon(
                Icons.search_rounded,
                size: 18,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            suffixIcon: _buildSuffixIcon(isDark),
            hintText: l10n.searchRestaurants,
            hintStyle: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            filled: true,
            fillColor: isDark ? const Color(0xFF2D2B3F) : Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey.shade200,
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
          onTap: () {
            if (!_searchFocusNode.hasFocus) {
              _searchFocusNode.requestFocus();
            }
          },
          onSubmitted: (value) {
            _dismissKeyboard();
          },
        ),
      ),
    );
  }

  Widget _buildSuffixIcon(bool isDark) {
    if (_searchController.text.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.all(6),
        child: IconButton(
          icon: Icon(
            Icons.clear_rounded,
            size: 18,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          onPressed: _clearSearch,
          tooltip: 'Clear search',
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(6),
      child: Icon(
        Icons.tune_rounded,
        size: 16,
        color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
          iconTheme: IconThemeData(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          leading: context.canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/'),
                ),
          title: Text(
            l10n.foodOrders,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1A29) : null,
            gradient: isDark
                ? null
                : LinearGradient(
                    colors: [Colors.grey[100]!, Colors.white],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: Column(
            children: [
              if (_showSearchBar) _buildSearchBox(),
              Expanded(
                child: FoodOrdersTab(
                  key: _foodTabKey,
                  onHasOrders: (hasOrders) {
                    if (_hasOrders != hasOrders) {
                      setState(() => _hasOrders = hasOrders);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

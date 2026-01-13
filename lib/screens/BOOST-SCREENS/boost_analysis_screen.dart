// lib/screens/boost_analysis_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/boost_analysis_provider.dart';
import '../../widgets/boostanalysis/ongoing_boosts_widget.dart';
import '../../widgets/boostanalysis/past_boosts_widget.dart';
import '../../widgets/boostanalysis/analysis_widget.dart';
import '../../generated/l10n/app_localizations.dart';

class BoostAnalysisScreen extends StatefulWidget {
  const BoostAnalysisScreen({Key? key}) : super(key: key);

  @override
  State<BoostAnalysisScreen> createState() => _BoostAnalysisScreenState();
}

class _BoostAnalysisScreenState extends State<BoostAnalysisScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _currentSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_onSearchChanged);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase().trim();
      setState(() {
        _currentSearchQuery = query;
      });

      // Update the provider's search query
      Provider.of<BoostAnalysisProvider>(context, listen: false)
          .updateSearchQuery(query);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _tabController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Widget _buildModernTabBar() {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.grey.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00A86B), Color(0xFF00C574)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00A86B).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Theme.of(context).brightness == Brightness.light
            ? Colors.grey[600]
            : Colors.grey[400],
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: [
          _buildModernTab(l10n.analysis, Icons.analytics_rounded),
          _buildModernTab(l10n.ongoingBoosts, Icons.trending_up_rounded),
          _buildModernTab(l10n.pastBoosts, Icons.history_rounded),
        ],
      ),
    );
  }

  Widget _buildModernTab(String text, IconData icon) {
    return Tab(
      height: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox(String hint) {
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
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _focusNode.unfocus(),
          style: GoogleFonts.inter(
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
            suffixIcon: _searchController.text.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.all(6),
                    child: IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _focusNode.unfocus();
                        setState(() {
                          _currentSearchQuery = '';
                        });
                        // Clear search in provider
                        Provider.of<BoostAnalysisProvider>(context,
                                listen: false)
                            .clearSearch();
                      },
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    ),
                  ),
            hintText: hint,
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
        ),
      ),
    );
  }

  Future<void> _pickDateRange(BoostAnalysisProvider provider) async {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final backgroundColor = isLight ? Colors.white : Colors.grey[900]!;
    const jadeGreen = Color(0xFF00A86B);

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: provider.selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: jadeGreen,
              onPrimary: Colors.white,
              surface: backgroundColor,
              onSurface: theme.colorScheme.onSurface,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: isLight ? Colors.black : Colors.white,
              ),
            ),
            dialogTheme: DialogThemeData(backgroundColor: backgroundColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      await provider.updateDateRange(picked);
    }
  }

  void _unfocus() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const jadeGreen = Color(0xFF00A86B);

    return ChangeNotifierProvider<BoostAnalysisProvider>(
      create: (_) => BoostAnalysisProvider(),
      builder: (context, child) {
        final provider = Provider.of<BoostAnalysisProvider>(context);
        final isLoading = provider.isLoading;
        final hasDateFilter = provider.selectedDateRange != null;

        return GestureDetector(
          onTap: _unfocus,
          behavior: HitTestBehavior.translucent,
          child: Scaffold(
            backgroundColor: isDark
                ? const Color(0xFF1C1A29)
                : const Color.fromARGB(255, 244, 244, 244),
            appBar: AppBar(
              elevation: 0,
              backgroundColor: isDark ? null : Colors.white,
              iconTheme: IconThemeData(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              title: Text(
                l10n.boostAnalysisTitle,
                style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              actions: [
                // Date range filter button with active indicator
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.date_range_rounded,
                        color: hasDateFilter
                            ? jadeGreen
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                      onPressed: () => _pickDateRange(provider),
                    ),
                    if (hasDateFilter)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: jadeGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                // Clear date filter button (only shown when filter is active)
                if (hasDateFilter)
                  IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 20,
                    ),
                    onPressed: () => provider.clearDateRange(),
                    tooltip: 'Clear date filter',
                  ),
              ],
            ),
            body: SafeArea(
              child: Container(
                color: isDark
                    ? const Color(0xFF1C1A29)
                    : const Color.fromARGB(255, 244, 244, 244),
                child: Column(
                  children: [
                    _buildSearchBox(l10n.searchProducts),
                    _buildModernTabBar(),
                    Expanded(
                      child: isLoading
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark ? Colors.tealAccent : Colors.teal,
                                    ),
                                    strokeWidth: 3,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n.loading,
                                    style: GoogleFonts.inter(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey[600],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildAnalysisTab(context),
                                _buildOngoingTab(context),
                                _buildPastTab(context),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnalysisTab(BuildContext context) {
    final provider = Provider.of<BoostAnalysisProvider>(context);
    final ongoing = provider.filteredOngoingBoosts
        .where((item) => item.itemType == 'product')
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: AnalysisWidget(items: ongoing),
    );
  }

  Widget _buildOngoingTab(BuildContext context) {
    final provider = Provider.of<BoostAnalysisProvider>(context);
    final ongoing = provider.filteredOngoingBoosts
        .where((item) => item.itemType == 'product')
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: OngoingBoostsWidget(ongoingBoosts: ongoing),
    );
  }

  Widget _buildPastTab(BuildContext context) {
    final provider = Provider.of<BoostAnalysisProvider>(context);
    final pastDocs = provider.filteredPastBoostHistoryDocs
        .where((doc) => (doc['itemType'] ?? '') == 'product')
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: PastBoostsWidget(pastBoostHistory: pastDocs),
    );
  }
}

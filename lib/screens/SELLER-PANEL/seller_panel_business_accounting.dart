import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../generated/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SellerPanelBusinessAccounting extends StatefulWidget {
  final String businessId;
  final String businessType;

  const SellerPanelBusinessAccounting({
    super.key,
    required this.businessId,
    required this.businessType,
  });

  @override
  State<SellerPanelBusinessAccounting> createState() =>
      _SellerPanelBusinessAccountingState();
}

class _SellerPanelBusinessAccountingState
    extends State<SellerPanelBusinessAccounting> {
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  // Period: 0 = daily, 1 = weekly, 2 = monthly
  int _periodIndex = 0;
  String get _periodType => const ['daily', 'weekly', 'monthly'][_periodIndex];

  final _firestore = FirebaseFirestore.instance;

  // Date state
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));
  late int _selectedYear = DateTime.now().year;
  late int _selectedMonth = DateTime.now().month == 1
      ? 12
      : DateTime.now().month - 1;
  int _selectedMonthYear = DateTime.now().month == 1
      ? DateTime.now().year - 1
      : DateTime.now().year;

  bool _isGenerating = false;
  bool _isLoadingReports = true;
  List<Map<String, dynamic>> _reports = [];

  bool get _isRestaurant => widget.businessType == 'restaurant';

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  // ── ISO Week helpers ───────────────────────────────────────

  int _isoWeekNumber(DateTime date) {
    final dayOfYear =
        date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final week = ((dayOfYear - date.weekday + 10) / 7).floor();
    if (week < 1) return _weeksInYear(date.year - 1);
    if (week > _weeksInYear(date.year)) return 1;
    return week;
  }

  int _isoWeekYear(DateTime date) {
    final week = _isoWeekNumber(date);
    if (date.month == 1 && week > 50) return date.year - 1;
    if (date.month == 12 && week == 1) return date.year + 1;
    return date.year;
  }

  int _weeksInYear(int year) {
    final dec28 = DateTime(year, 12, 28);
    final dayOfYear =
        dec28.difference(DateTime(year, 1, 1)).inDays + 1;
    return ((dayOfYear - dec28.weekday + 10) / 7).floor();
  }

  DateTime _mondayOfIsoWeek(int year, int week) {
    final jan4 = DateTime(year, 1, 4);
    final firstMonday =
        jan4.subtract(Duration(days: jan4.weekday - 1));
    return firstMonday.add(Duration(days: (week - 1) * 7));
  }

  dynamic _deepCast(dynamic data) {
  if (data is Map) {
    return Map<String, dynamic>.fromEntries(
      data.entries.map((e) => MapEntry(e.key.toString(), _deepCast(e.value))),
    );
  }
  if (data is List) {
    return data.map(_deepCast).toList();
  }
  return data;
}

  // ── Cloud Function calls ───────────────────────────────────

 Future<void> _loadReports() async {
  setState(() => _isLoadingReports = true);
  try {
    Query q = _firestore
        .collection('business-reports')
        .doc(widget.businessId)
        .collection('reports')
        .orderBy('periodStart', descending: true)
        .limit(30);

    if (_periodType != 'all') {
      q = q.where('period', isEqualTo: _periodType);
    }

    final snap = await q.get();
    if (!mounted) return;
    setState(() {
      _reports = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          ...data,
          'periodKey': doc.id,
          'periodStart': (data['periodStart'] as Timestamp?)?.toDate().toIso8601String(),
          'periodEnd': (data['periodEnd'] as Timestamp?)?.toDate().toIso8601String(),
          'generatedAt': (data['generatedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();
      _isLoadingReports = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoadingReports = false);
    debugPrint('Error loading reports: $e');
  }
}

  Future<void> _generateReport() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isGenerating = true);

    try {
      final params = <String, dynamic>{
        'businessId': widget.businessId,
        'businessType': widget.businessType,
        'period': _periodType,
      };

      switch (_periodType) {
        case 'daily':
          params['date'] = DateFormat('yyyy-MM-dd').format(_selectedDate);
          break;
        case 'weekly':
          params['year'] = _isoWeekYear(_selectedDate);
          params['week'] = _isoWeekNumber(_selectedDate);
          break;
        case 'monthly':
          params['year'] = _selectedMonthYear;
          params['month'] = _selectedMonth;
          break;
      }

      final result =
          await _functions.httpsCallable('generateBusinessReport').call(params);
      final data = _deepCast(result.data) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() => _isGenerating = false);
      _loadReports();
      _showReportDetail(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.reportGenerationFailed),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          l10n.salesInformation,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: isDark ? null : Colors.white,
      ),
      body: Column(
        children: [
          _buildPeriodSelector(l10n, isDark),
          _buildDatePicker(l10n, isDark),
          _buildGenerateButton(l10n),
          const SizedBox(height: 8),
          Divider(
            color: isDark ? Colors.white12 : Colors.grey[200],
            height: 1,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  l10n.generatedReports,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isDark ? Colors.white70 : Colors.grey[800],
                  ),
                ),
                const Spacer(),
                if (_isLoadingReports)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildReportsList(l10n, isDark)),
        ],
      ),
    );
  }

  // ── Period selector ────────────────────────────────────────

  Widget _buildPeriodSelector(AppLocalizations l10n, bool isDark) {
    final labels = [l10n.dailyReport, l10n.weeklyReport, l10n.monthlyReport];

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(3, (i) {
          final selected = _periodIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_periodIndex != i) {
                  setState(() => _periodIndex = i);
                  _loadReports();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF667EEA).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                    color: selected
                        ? Colors.white
                        : (isDark ? Colors.white54 : Colors.grey[600]),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Date picker ────────────────────────────────────────────

  Widget _buildDatePicker(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.selectPeriod,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          _periodIndex == 2
              ? _buildMonthSelector(isDark)
              : _buildDateTile(l10n, isDark),
        ],
      ),
    );
  }

  Widget _buildDateTile(AppLocalizations l10n, bool isDark) {
    final locale = Localizations.localeOf(context).languageCode;
    String displayText;

    if (_periodIndex == 0) {
      displayText = DateFormat.yMMMd(locale).format(_selectedDate);
    } else {
      final week = _isoWeekNumber(_selectedDate);
      final year = _isoWeekYear(_selectedDate);
      final monday = _mondayOfIsoWeek(year, week);
      final sunday = monday.add(const Duration(days: 6));
      displayText =
          '${l10n.weekLabel(week.toString(), year.toString())}  '
          '(${DateFormat.MMMd(locale).format(monday)} – '
          '${DateFormat.MMMd(locale).format(sunday)})';
    }

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx)
                  .colorScheme
                  .copyWith(primary: const Color(0xFF667EEA)),
            ),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _selectedDate = picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: Color(0xFF667EEA)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded,
                color: isDark ? Colors.white38 : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    final locale = Localizations.localeOf(context).languageCode;
    final months = List.generate(
      12,
      (i) => DateFormat.MMMM(locale).format(DateTime(2024, i + 1)),
    );
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 2019, (i) => 2020 + i);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedMonth,
                isExpanded: true,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                dropdownColor:
                    isDark ? const Color(0xFF2C2C2C) : Colors.white,
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(
                      value: i + 1, child: Text(months[i])),
                ),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedMonth = v);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedMonthYear,
                isExpanded: true,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                dropdownColor:
                    isDark ? const Color(0xFF2C2C2C) : Colors.white,
                items: years.reversed
                    .map((y) => DropdownMenuItem(
                        value: y, child: Text(y.toString())))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedMonthYear = v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Generate button ────────────────────────────────────────

  Widget _buildGenerateButton(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _isGenerating ? null : _generateReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6200),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            disabledBackgroundColor:
                const Color(0xFFFF6200).withOpacity(0.5),
          ),
          child: _isGenerating
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(l10n.generatingReport,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bar_chart_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.generateReport,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Reports list ───────────────────────────────────────────

  Widget _buildReportsList(AppLocalizations l10n, bool isDark) {
    if (_isLoadingReports && _reports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_chart_outlined_rounded,
                size: 56,
                color: isDark ? Colors.white24 : Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              l10n.noReportsYet,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                l10n.noReportsYetDesc,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) =>
            _buildReportCard(_reports[i], isDark),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report, bool isDark) {
    final periodLabel = report['periodLabel'] as String? ??
        report['periodKey'] as String? ??
        '';
    final periodKey = report['periodKey'] as String? ?? '';
    final generatedAt = report['generatedAt'] as String?;

    // Summary metric
    final double revenue;
    final int orders;
    if (_isRestaurant) {
      revenue = (report['grossRevenue'] as num?)?.toDouble() ?? 0;
      orders = report['totalOrders'] as int? ?? 0;
    } else {
      revenue = (report['totalRevenue'] as num?)?.toDouble() ?? 0;
      orders = report['orderCount'] as int? ?? 0;
    }

    String timeAgo = '';
    if (generatedAt != null) {
      try {
        final dt = DateTime.parse(generatedAt);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h';
        } else {
          timeAgo = '${diff.inDays}d';
        }
      } catch (_) {}
    }

    return InkWell(
      onTap: () => _showReportDetail(report),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white12
                : Colors.grey.withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _periodIndex == 0
                    ? Icons.today_rounded
                    : _periodIndex == 1
                        ? Icons.date_range_rounded
                        : Icons.calendar_month_rounded,
                size: 20,
                color: const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(periodLabel,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    '$orders ${AppLocalizations.of(context).ordersLabel} • $timeAgo',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color:
                          isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '₺${revenue.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: const Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? Colors.white24 : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ── Report detail bottom sheet ─────────────────────────────

  void _showReportDetail(Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(l10n.reportDetails,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                data['periodLabel'] as String? ?? '',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.grey[500],
                ),
              ),
              const SizedBox(height: 20),
              if (_isRestaurant)
                ..._restaurantMetrics(data, l10n, isDark)
              else
                ..._shopMetrics(data, l10n, isDark),
            ],
          ),
          ),
        ),
      ),
    );
  }

  // ── Restaurant metrics ─────────────────────────────────────

  List<Widget> _restaurantMetrics(
      Map<String, dynamic> d, AppLocalizations l10n, bool isDark) {
    return [
      _grid([
        _M(l10n.totalOrders, '${d['totalOrders'] ?? 0}',
            Icons.receipt_long_rounded, const Color(0xFF667EEA)),
        _M(l10n.completedOrders, '${d['completedOrders'] ?? 0}',
            Icons.check_circle_rounded, const Color(0xFF4CAF50)),
        _M(l10n.activeOrders, '${d['activeOrders'] ?? 0}',
            Icons.hourglass_top_rounded, const Color(0xFFFFC107)),
        _M(l10n.cancelledOrders, '${d['cancelledOrders'] ?? 0}',
            Icons.cancel_rounded, const Color(0xFFE53935)),
      ], isDark),
      const SizedBox(height: 12),
      _grid([
        _M(l10n.grossRevenue,
            '₺${_fmt(d['grossRevenue'])}',
            Icons.attach_money_rounded, const Color(0xFF4CAF50)),
        _M(l10n.deliveredRevenue,
            '₺${_fmt(d['deliveredRevenue'])}',
            Icons.local_shipping_rounded, const Color(0xFF2196F3)),
        _M(l10n.averageOrderValue,
            '₺${_fmt(d['averageOrderValue'])}',
            Icons.trending_up_rounded, const Color(0xFF9C27B0)),
        _M(l10n.totalItemsSold, '${d['totalItemsSold'] ?? 0}',
            Icons.inventory_2_rounded, const Color(0xFFFF6200)),
      ], isDark),
      const SizedBox(height: 20),
      if (d['paymentBreakdown'] != null) ...[
        _section(l10n.paymentMethods, isDark),
        const SizedBox(height: 8),
        _breakdownCards(
          d['paymentBreakdown'] as Map<String, dynamic>,
          isDark,
          {'card': l10n.cardPayment, 'pay_at_door': l10n.payAtDoor},
        ),
        const SizedBox(height: 16),
      ],
      if (d['deliveryTypeBreakdown'] != null) ...[
        _section(l10n.deliveryTypes, isDark),
        const SizedBox(height: 8),
        _breakdownCards(
          d['deliveryTypeBreakdown'] as Map<String, dynamic>,
          isDark,
          {
            'delivery': l10n.deliveryLabel,
            'pickup': l10n.pickupLabel,
          },
        ),
        const SizedBox(height: 16),
      ],
      if (d['topItems'] != null &&
          (d['topItems'] as List).isNotEmpty) ...[
        _section(l10n.topSellingItems, isDark),
        const SizedBox(height: 8),
        ...(d['topItems'] as List).take(10).map((item) {
          final i = Map<String, dynamic>.from(item as Map);
          return _itemTile(
            i['name'] as String? ?? '',
            i['quantity'] as int? ?? 0,
            '₺${_fmt(i['revenue'])}',
            isDark,
          );
        }),
      ],
    ];
  }

  // ── Shop metrics ───────────────────────────────────────────

  List<Widget> _shopMetrics(
      Map<String, dynamic> d, AppLocalizations l10n, bool isDark) {
    return [
      _grid([
        _M(l10n.totalRevenue, '₺${_fmt(d['totalRevenue'])}',
            Icons.attach_money_rounded, const Color(0xFF4CAF50)),
        _M(l10n.netRevenue, '₺${_fmt(d['netRevenue'])}',
            Icons.account_balance_wallet_rounded,
            const Color(0xFF2196F3)),
        _M(l10n.totalCommission,
            '₺${_fmt(d['totalCommission'])}',
            Icons.percent_rounded, const Color(0xFFFFC107)),
        _M(l10n.orderCount, '${d['orderCount'] ?? 0}',
            Icons.receipt_long_rounded, const Color(0xFF667EEA)),
      ], isDark),
      const SizedBox(height: 12),
      _grid([
        _M(l10n.averageOrderValue,
            '₺${_fmt(d['averageOrderValue'])}',
            Icons.trending_up_rounded, const Color(0xFF9C27B0)),
        _M(l10n.totalItemCount, '${d['totalItemCount'] ?? 0}',
            Icons.inventory_2_rounded, const Color(0xFFFF6200)),
      ], isDark),
      const SizedBox(height: 20),
      if (d['categories'] != null &&
          (d['categories'] as Map).isNotEmpty) ...[
        _section(l10n.categoryBreakdown, isDark),
        const SizedBox(height: 8),
        ...(d['categories'] as Map<String, dynamic>).entries.map((e) {
          final cat = Map<String, dynamic>.from(e.value as Map);
          return _itemTile(
            e.key,
            cat['quantity'] as int? ?? 0,
            '₺${_fmt(cat['revenue'])}',
            isDark,
          );
        }),
      ],
    ];
  }

  // ── Shared UI components ───────────────────────────────────

  String _fmt(dynamic v) =>
      ((v as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  Widget _grid(List<_M> metrics, bool isDark) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: metrics.map((m) => _metricCard(m, isDark)).toList(),
    );
  }

  Widget _metricCard(_M m, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white12
              : Colors.grey.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(m.icon, size: 14, color: m.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  m.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.grey[500],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(m.value,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _section(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: isDark ? Colors.white70 : Colors.grey[800],
      ),
    );
  }

  Widget _breakdownCards(
    Map<String, dynamic> breakdown,
    bool isDark,
    Map<String, String> labels,
  ) {
    return Column(
      children: breakdown.entries.map((e) {
        final data = Map<String, dynamic>.from(e.value as Map);
        final label = labels[e.key] ?? e.key;
        final count = data['count'] as int? ?? 0;
        final amount =
            (data['amount'] as num?)?.toDouble() ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500, fontSize: 14)),
              ),
              Text('$count',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color:
                        isDark ? Colors.white38 : Colors.grey[500],
                  )),
              const SizedBox(width: 16),
              Text(
                '₺${amount.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _itemTile(
      String name, int qty, String revenue, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          Text('×$qty',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey[500],
              )),
          const SizedBox(width: 12),
          Text(revenue,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: const Color(0xFF4CAF50),
              )),
        ],
      ),
    );
  }
}

class _M {
  final String label, value;
  final IconData icon;
  final Color color;
  const _M(this.label, this.value, this.icon, this.color);
}
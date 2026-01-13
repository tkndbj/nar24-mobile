// lib/widgets/boostanalysis/analysis_widget.dart

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/boost_analysis_provider.dart';

/// Modern color scheme
const Color primaryGreen = Color(0xFF00A86B);
const Color accentCoral = Color(0xFFFF7F50);
const Color blueAccent = Color(0xFF3B82F6);
const Color darkBlue = Color(0xFF1A365D);

class AnalysisWidget extends StatelessWidget {
  final List<BoostedItem> items;

  const AnalysisWidget({Key? key, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          blueAccent.withOpacity(0.2),
                          blueAccent.withOpacity(0.1)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      size: 40,
                      color: blueAccent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.noOngoingBoosts,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  blueAccent.withOpacity(0.1),
                  blueAccent.withOpacity(0.05)
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  color: blueAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.analysis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: blueAccent,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: blueAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Charts Container
          Container(
            height: 320,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  width: 280,
                  margin: EdgeInsets.only(
                    right: index == items.length - 1 ? 0 : 16,
                  ),
                  child: _buildSingleItemChart(context, item, isDark),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleItemChart(
      BuildContext context, BoostedItem item, bool isDark) {
    final l10n = AppLocalizations.of(context);

    // Calculate incremental metrics since boost started
    final displayedImpressions = (item.boostedImpressionCount ?? 0) -
        (item.boostImpressionCountAtStart ?? 0);
    final displayedClicks =
        (item.clickCount ?? 0) - (item.boostClickCountAtStart ?? 0);

    final List<_MetricData> data = [
      _MetricData(l10n.impressions, displayedImpressions, accentCoral),
      _MetricData(l10n.clicks, displayedClicks, primaryGreen),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Chart Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : darkBlue,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MetricPill(
                      icon: Icons.visibility_rounded,
                      value: displayedImpressions.toString(),
                      color: accentCoral,
                    ),
                    const SizedBox(width: 8),
                    _MetricPill(
                      icon: Icons.touch_app_rounded,
                      value: displayedClicks.toString(),
                      color: primaryGreen,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Chart Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: const AxisLine(width: 0),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                ),
                primaryYAxis: NumericAxis(
                  majorGridLines: MajorGridLines(
                    width: 1,
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.2),
                  ),
                  axisLine: const AxisLine(width: 0),
                  labelStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                ),
                plotAreaBorderWidth: 0,
                legend: Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                  textStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  textStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : darkBlue,
                  ),
                ),
                series: <CartesianSeries<_MetricData, String>>[
                  ColumnSeries<_MetricData, String>(
                    dataSource: data,
                    xValueMapper: (metric, _) => metric.label,
                    yValueMapper: (metric, _) => metric.value,
                    pointColorMapper: (metric, _) => metric.color,
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    width: 0.8,
                    spacing: 0.3,
                    dataLabelSettings: DataLabelSettings(
                      isVisible: true,
                      textStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : darkBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _MetricPill({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  final String label;
  final int value;
  final Color color;

  _MetricData(this.label, this.value, this.color);
}

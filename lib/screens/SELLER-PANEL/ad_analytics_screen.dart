import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/ad_analytics_service.dart';
import 'package:fl_chart/fl_chart.dart';

class AdAnalyticsScreen extends StatefulWidget {
  final String adId;
  final String adType;
  final String adName;

  const AdAnalyticsScreen({
    super.key,
    required this.adId,
    required this.adType,
    required this.adName,
  });

  @override
  State<AdAnalyticsScreen> createState() => _AdAnalyticsScreenState();
}

class _AdAnalyticsScreenState extends State<AdAnalyticsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _analytics;
  int _touchedGenderIndex = -1;
  int _touchedAgeIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    final analytics = await AdAnalyticsService.getAdAnalytics(
      adId: widget.adId,
      adType: widget.adType,
    );

    setState(() {
      _analytics = analytics;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1A1B23) : Colors.white,
        title: Text(
          l10n.adAnalytics,
          style: GoogleFonts.figtree(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? _buildShimmerLoading(isDark)
            : _analytics == null
                ? _buildErrorState(isDark, l10n)
                : _buildAnalyticsDashboard(isDark, l10n),
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    final baseColor = isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3D3D4A) : const Color(0xFFF5F5F5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metric cards row shimmer
            Row(
              children: [
                Expanded(child: _buildMetricCardShimmer(isDark)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricCardShimmer(isDark)),
              ],
            ),
            const SizedBox(height: 12),
            // Full width metric card shimmer
            _buildMetricCardShimmer(isDark),
            const SizedBox(height: 24),
            // Section title shimmer
            _buildShimmerBox(width: 150, height: 20, isDark: isDark),
            const SizedBox(height: 12),
            // Pie chart shimmer
            _buildPieChartShimmer(isDark),
            const SizedBox(height: 24),
            // Section title shimmer
            _buildShimmerBox(width: 120, height: 20, isDark: isDark),
            const SizedBox(height: 12),
            // Pie chart shimmer
            _buildPieChartShimmer(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCardShimmer(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon placeholder
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),
          // Value placeholder
          _buildShimmerBox(width: 80, height: 32, isDark: isDark),
          const SizedBox(height: 8),
          // Label placeholder
          _buildShimmerBox(width: 100, height: 14, isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildPieChartShimmer(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          // Pie chart placeholder (circular)
          Center(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
              ),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? const Color(0xFF1A1B23)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Legend placeholders
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendShimmer(isDark),
              const SizedBox(width: 16),
              _buildLegendShimmer(isDark),
              const SizedBox(width: 16),
              _buildLegendShimmer(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendShimmer(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        _buildShimmerBox(width: 50, height: 12, isDark: isDark),
      ],
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required bool isDark,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildAnalyticsDashboard(bool isDark, AppLocalizations l10n) {
    final totalClicks = _analytics!['totalClicks'] as int;
    final totalConversions = _analytics!['totalConversions'] as int;
    final conversionRate = _analytics!['conversionRate'] as double;
    final demographics = _analytics!['demographics'] as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Cards
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    isDark,
                    l10n.totalClicks,
                    totalClicks.toString(),
                    Icons.touch_app_rounded,
                    const Color(0xFF667EEA),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    isDark,
                    l10n.conversions,
                    totalConversions.toString(),
                    Icons.shopping_cart_rounded,
                    const Color(0xFF38A169),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricCard(
              isDark,
              l10n.conversionRate,
              '${conversionRate.toStringAsFixed(2)}%',
              Icons.trending_up_rounded,
              const Color(0xFF9F7AEA),
              fullWidth: true,
            ),
            const SizedBox(height: 24),

            // Gender Distribution
            Text(
              l10n.genderDistribution,
              style: GoogleFonts.figtree(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 12),
            _buildGenderPieChart(
                isDark, demographics['gender'] as Map<String, dynamic>, l10n),
            const SizedBox(height: 24),

            // Age Groups
            Text(
              l10n.ageGroups,
              style: GoogleFonts.figtree(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 12),
            _buildAgeGroupPieChart(isDark,
                demographics['ageGroups'] as Map<String, dynamic>, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    bool isDark,
    String label,
    String value,
    IconData icon,
    Color color, {
    bool fullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 37, 35, 54) : null,
        gradient: isDark
            ? null
            : LinearGradient(
                colors: [Colors.white, const Color(0xFFF8FAFC)],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.figtree(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A202C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.figtree(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderPieChart(
      bool isDark, Map<String, dynamic> genderData, AppLocalizations l10n) {
    if (genderData.isEmpty) {
      return _buildNoDataCard(isDark, l10n.noGenderDataAvailable);
    }

    final total =
        genderData.values.fold<int>(0, (sum, value) => sum + (value as int));
    final colors = {
      'Male': const Color(0xFF667EEA),
      'Female': const Color(0xFF9F7AEA),
      'Other': const Color(0xFF38A169),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedGenderIndex = -1;
                        return;
                      }
                      _touchedGenderIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections:
                    genderData.entries.toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isTouched = index == _touchedGenderIndex;
                  final fontSize = isTouched ? 16.0 : 14.0;
                  final radius = isTouched ? 65.0 : 60.0;
                  final percentage = (data.value / total * 100);

                  return PieChartSectionData(
                    color: colors[data.key] ?? const Color(0xFF94A3B8),
                    value: data.value.toDouble(),
                    title: '${percentage.toStringAsFixed(1)}%',
                    radius: radius,
                    titleStyle: GoogleFonts.figtree(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: genderData.entries.map((entry) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[entry.key] ?? const Color(0xFF94A3B8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.key} (${entry.value})',
                    style: GoogleFonts.figtree(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeGroupPieChart(
      bool isDark, Map<String, dynamic> ageGroupData, AppLocalizations l10n) {
    if (ageGroupData.isEmpty) {
      return _buildNoDataCard(isDark, l10n.noAgeGroupDataAvailable);
    }

    final total =
        ageGroupData.values.fold<int>(0, (sum, value) => sum + (value as int));
    final colors = [
      const Color(0xFF667EEA),
      const Color(0xFF9F7AEA),
      const Color(0xFF38A169),
      const Color(0xFFED8936),
      const Color(0xFFE53E3E),
      const Color(0xFF3182CE),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedAgeIndex = -1;
                        return;
                      }
                      _touchedAgeIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections:
                    ageGroupData.entries.toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isTouched = index == _touchedAgeIndex;
                  final fontSize = isTouched ? 16.0 : 14.0;
                  final radius = isTouched ? 65.0 : 60.0;
                  final percentage = (data.value / total * 100);

                  return PieChartSectionData(
                    color: colors[index % colors.length],
                    value: data.value.toDouble(),
                    title: '${percentage.toStringAsFixed(1)}%',
                    radius: radius,
                    titleStyle: GoogleFonts.figtree(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children:
                ageGroupData.entries.toList().asMap().entries.map((entry) {
              final index = entry.key;
              final data = entry.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${data.key} (${data.value})',
                    style: GoogleFonts.figtree(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataCard(bool isDark, String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: Text(
          message,
          style: GoogleFonts.figtree(
            fontSize: 14,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.failedToLoadAnalytics,
            style: GoogleFonts.figtree(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A202C),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAnalytics,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}

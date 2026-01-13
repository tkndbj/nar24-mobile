// lib/widgets/boostanalysis/ongoing_boosts_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/boost_analysis_provider.dart';
import '../product_card.dart';
import '../../screens/USER-PROFILE/my_products_screen.dart';

/// Modern color scheme
const Color primaryGreen = Color(0xFF00A86B);
const Color accentCoral = Color(0xFFFF7F50);
const Color blueAccent = Color(0xFF3B82F6);
const Color darkBlue = Color(0xFF1A365D);

class OngoingBoostsWidget extends StatelessWidget {
  final List<BoostedItem> ongoingBoosts;

  const OngoingBoostsWidget({Key? key, required this.ongoingBoosts})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (ongoingBoosts.isEmpty) {
      return SafeArea(
        child: Container(
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
                    // Animated boost icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryGreen.withOpacity(0.2),
                            primaryGreen.withOpacity(0.1)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        size: 40,
                        color: primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      l10n.noActiveBoostMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // CTA Button
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [primaryGreen, Color(0xFF059669)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MyProductsScreen(),
                              ),
                            );
                          },
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.rocket_launch_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.boostProductButton,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryGreen.withOpacity(0.1),
                    primaryGreen.withOpacity(0.05)
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.trending_up_rounded,
                    color: primaryGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.ongoingBoosts,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: primaryGreen,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${ongoingBoosts.length}',
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

            // Ongoing Boosts List
            ListView.separated(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(), // This is fine now because parent scrolls
              itemCount: ongoingBoosts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = ongoingBoosts[index];
                return _OngoingBoostCard(boostedItem: item);
              },
            ),
            const SizedBox(height: 16), // Bottom padding
          ],
        ),
      ),
    );
  }
}

class _OngoingBoostCard extends StatelessWidget {
  final BoostedItem boostedItem;

  const _OngoingBoostCard({required this.boostedItem});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Calculate metrics
    final ongoingImpressions = (boostedItem.boostedImpressionCount -
            boostedItem.boostImpressionCountAtStart)
        .clamp(0, 999999999);
    final ongoingClicks =
        ((boostedItem.clickCount) - (boostedItem.boostClickCountAtStart ?? 0))
            .clamp(0, 999999999);
    final ongoingCTR = _calculateCTR(ongoingClicks, ongoingImpressions);

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
          // Product and Timer Section
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Product Card (Compact)
                Expanded(
                  flex: 3,
                  child: boostedItem.product != null
                      ? ProductCard(
                          product: boostedItem.product!,
                          scaleFactor: 0.8,
                          internalScaleFactor: 0.7,
                          portraitImageHeight: 100,
                        )
                      : Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(Icons.image_not_supported,
                                color: Colors.grey),
                          ),
                        ),
                ),
                const SizedBox(width: 16),

                // Timer and Basic Stats
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (boostedItem.boostEndTime != null)
                        _BoostTimer(
                          endTime: boostedItem.boostEndTime!.toDate(),
                          l10n: l10n,
                        ),
                      const SizedBox(height: 12),

                      // Quick Stats
                      _QuickStat(
                        icon: Icons.visibility_rounded,
                        value: ongoingImpressions.toString(),
                        label: l10n.impressions,
                        color: accentCoral,
                      ),
                      const SizedBox(height: 6),
                      _QuickStat(
                        icon: Icons.touch_app_rounded,
                        value: ongoingClicks.toString(),
                        label: l10n.clicks,
                        color: primaryGreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Detailed Metrics Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.grey[50],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    icon: Icons.visibility_rounded,
                    label: l10n.impressions,
                    value: ongoingImpressions.toString(),
                    color: accentCoral,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.touch_app_rounded,
                    label: l10n.clicks,
                    value: ongoingClicks.toString(),
                    color: primaryGreen,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.analytics_rounded,
                    label: 'CTR',
                    value: '$ongoingCTR%',
                    color: blueAccent,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _calculateCTR(num clicks, num impressions) {
    if (impressions == 0) return '0.0';
    double ctr = (clicks / impressions) * 100;
    return ctr.toStringAsFixed(1);
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _QuickStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 18,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoostTimer extends StatefulWidget {
  final DateTime endTime;
  final AppLocalizations l10n;

  const _BoostTimer({
    required this.endTime,
    required this.l10n,
  });

  @override
  State<_BoostTimer> createState() => _BoostTimerState();
}

class _BoostTimerState extends State<_BoostTimer> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _computeRemaining();
    });
  }

  void _computeRemaining() {
    final now = DateTime.now();
    setState(() {
      _remaining = widget.endTime.difference(now);
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryGreen.withOpacity(0.1),
            primaryGreen.withOpacity(0.05)
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primaryGreen.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_rounded,
                color: primaryGreen,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                widget.l10n.boosted,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _formatted,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: primaryGreen,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

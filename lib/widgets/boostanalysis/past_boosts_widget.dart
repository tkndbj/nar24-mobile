// lib/widgets/boostanalysis/past_boosts_widget.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/boost_analysis_provider.dart';

/// Modern color scheme
const Color primaryGreen = Color(0xFF00A86B);
const Color accentCoral = Color(0xFFFF7F50);
const Color blueAccent = Color(0xFF3B82F6);
const Color darkBlue = Color(0xFF1A365D);
const Color maleColor = Color(0xFF3B82F6); // Blue
const Color femaleColor = Color(0xFFEC4899); // Pink
const Color otherColor = Color(0xFF8B5CF6); // Purple

class PastBoostsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> pastBoostHistory;

  const PastBoostsWidget({
    Key? key,
    required this.pastBoostHistory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<BoostAnalysisProvider>(context, listen: false);

    if (pastBoostHistory.isEmpty) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
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
                    Icon(
                      Icons.history_rounded,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noPastBoosts,
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
        ),
      );
    }

    return SafeArea(
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          // Load more when user reaches 80% of scroll (better UX than waiting for exact bottom)
          if (!provider.isLoadingMore &&
              provider.hasMoreHistory &&
              scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent * 0.8) {
            provider.loadMorePastBoosts();
          }
          return false;
        },
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
                      Icons.analytics_rounded,
                      color: primaryGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.pastBoosts,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primaryGreen,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${pastBoostHistory.length}',
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

              // Boost History List
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pastBoostHistory.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final boostDoc = pastBoostHistory[index];
                  return _PastBoostCard(boostDoc: boostDoc);
                },
              ),

              // Loading indicator at bottom
              Consumer<BoostAnalysisProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoadingMore) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(primaryGreen),
                        ),
                      ),
                    );
                  } else if (!provider.hasMoreHistory &&
                      pastBoostHistory.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                    );
                  }
                  return const SizedBox(height: 16);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastBoostCard extends StatefulWidget {
  final Map<String, dynamic> boostDoc;

  const _PastBoostCard({required this.boostDoc});

  @override
  State<_PastBoostCard> createState() => _PastBoostCardState();
}

class _PastBoostCardState extends State<_PastBoostCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Extract denormalized data
    final String itemName = widget.boostDoc['itemName'] ?? 'Unnamed Product';
    final String? productImage = widget.boostDoc['productImage'];
    final double averageRating = (widget.boostDoc['averageRating'] ?? 0).toDouble();
    final num price = widget.boostDoc['price'] ?? 0;
    final String currency = widget.boostDoc['currency'] ?? 'TL';

    // Boost metrics
    final int impressionsDuringBoost =
        widget.boostDoc['impressionsDuringBoost']?.toInt() ?? 0;
    final int clicksDuringBoost = widget.boostDoc['clicksDuringBoost']?.toInt() ?? 0;
    final double ctr = impressionsDuringBoost > 0
        ? (clicksDuringBoost / impressionsDuringBoost) * 100
        : 0.0;

    // Timestamps
    final Timestamp? startTime = widget.boostDoc['boostStartTime'];
    final Timestamp? endTime = widget.boostDoc['boostEndTime'];
    final String duration = _calculateDuration(startTime, endTime);

    // Demographics data
    final demographics =
        widget.boostDoc['demographics'] as Map<String, dynamic>?;
    final viewerAgeGroups =
        widget.boostDoc['viewerAgeGroups'] as Map<String, dynamic>?;

    final hasDemographics = (demographics != null && demographics.isNotEmpty) ||
        (viewerAgeGroups != null && viewerAgeGroups.isNotEmpty);

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Product Info Section
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Product Image
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[200],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: productImage != null
                          ? CachedNetworkImage(
                              imageUrl: productImage,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                                child:
                                    const Icon(Icons.image, color: Colors.grey),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image,
                                    color: Colors.grey),
                              ),
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.image, color: Colors.grey),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Product Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Price and Rating Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$price $currency',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primaryGreen,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (averageRating > 0) ...[
                              Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Colors.amber[600],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                averageRating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Duration
                        Text(
                          'Duration: $duration',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Metrics Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color.fromARGB(255, 37, 35, 54) : Colors.grey[50],
              ),
              child: Row(
                children: [
                  // Impressions
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.visibility_rounded,
                      label: l10n.impressions,
                      value: impressionsDuringBoost.toString(),
                      color: accentCoral,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Clicks
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.touch_app_rounded,
                      label: l10n.clicks,
                      value: clicksDuringBoost.toString(),
                      color: primaryGreen,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // CTR
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.analytics_rounded,
                      label: 'CTR',
                      value: '${ctr.toStringAsFixed(1)}%',
                      color: blueAccent,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),

            // Demographics Section (Expandable)
            if (hasDemographics)
              Column(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color.fromARGB(255, 37, 35, 54)
                            : Colors.grey[50],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_rounded,
                            size: 18,
                            color: isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getLocalizedDemographics(l10n),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                              fontFamily: 'Figtree',
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isExpanded)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color.fromARGB(255, 37, 35, 54)
                            : Colors.grey[50],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gender Demographics
                          if (demographics != null &&
                              demographics.isNotEmpty) ...[
                            _buildSectionHeader(
                                l10n, _getLocalizedGender(l10n), isDark),
                            const SizedBox(height: 8),
                            _buildGenderChart(demographics, l10n, isDark),
                            const SizedBox(height: 16),
                          ],

                          // Age Demographics
                          if (viewerAgeGroups != null &&
                              viewerAgeGroups.isNotEmpty) ...[
                            _buildSectionHeader(l10n, _getLocalizedAge(l10n), isDark),
                            const SizedBox(height: 8),
                            _buildAgeChart(viewerAgeGroups, l10n, isDark),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _calculateDuration(Timestamp? start, Timestamp? end) {
    if (start == null || end == null) return 'Unknown';

    final duration = end.toDate().difference(start.toDate());
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  Widget _buildSectionHeader(AppLocalizations l10n, String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
        fontFamily: 'Figtree',
      ),
    );
  }

  Widget _buildGenderChart(
      Map<String, dynamic> demographics, AppLocalizations l10n, bool isDark) {
    final total =
        demographics.values.fold<int>(0, (sum, val) => sum + (val as int));

    if (total == 0) {
      return Text(
        _getLocalizedNoData(l10n),
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[500],
          fontFamily: 'Figtree',
        ),
      );
    }

    return Column(
      children: demographics.entries.map((entry) {
        final gender = entry.key;
        final count = entry.value as int;
        final percentage = (count / total * 100);

        Color genderColor;
        IconData genderIcon;
        String genderLabel;

        switch (gender.toLowerCase()) {
          case 'male':
            genderColor = maleColor;
            genderIcon = Icons.male_rounded;
            genderLabel = _getLocalizedMale(l10n);
            break;
          case 'female':
            genderColor = femaleColor;
            genderIcon = Icons.female_rounded;
            genderLabel = _getLocalizedFemale(l10n);
            break;
          default:
            genderColor = otherColor;
            genderIcon = Icons.person_rounded;
            genderLabel = _getLocalizedOther(l10n);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(genderIcon, size: 16, color: genderColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          genderLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey[300]
                                : Colors.grey[700],
                            fontFamily: 'Figtree',
                          ),
                        ),
                        Text(
                          '$count (${percentage.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: genderColor,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor:
                            isDark ? Colors.grey[700] : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(genderColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAgeChart(Map<String, dynamic> ageGroups, AppLocalizations l10n, bool isDark) {
    final total =
        ageGroups.values.fold<int>(0, (sum, val) => sum + (val as int));

    if (total == 0) {
      return Text(
        _getLocalizedNoData(l10n),
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[500],
          fontFamily: 'Figtree',
        ),
      );
    }

    // Sort age groups in logical order
    final sortedEntries = ageGroups.entries.toList()
      ..sort((a, b) {
        final order = {
          'under18': 0,
          '18-24': 1,
          '25-34': 2,
          '35-44': 3,
          '45-54': 4,
          '55plus': 5,
          'unknown': 6,
        };
        return (order[a.key] ?? 999).compareTo(order[b.key] ?? 999);
      });

    return Column(
      children: sortedEntries.map((entry) {
        final ageGroup = entry.key;
        final count = entry.value as int;
        final percentage = (count / total * 100);

        final ageLabel = _getLocalizedAgeGroup(ageGroup, l10n);
        final ageColor = _getAgeGroupColor(ageGroup);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ageColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ageLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey[300]
                                : Colors.grey[700],
                            fontFamily: 'Figtree',
                          ),
                        ),
                        Text(
                          '$count (${percentage.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ageColor,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor:
                            isDark ? Colors.grey[700] : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(ageColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getAgeGroupColor(String ageGroup) {
    switch (ageGroup) {
      case 'under18':
        return const Color(0xFFEC4899); // Pink
      case '18-24':
        return const Color(0xFF8B5CF6); // Purple
      case '25-34':
        return const Color(0xFF3B82F6); // Blue
      case '35-44':
        return const Color(0xFF10B981); // Emerald
      case '45-54':
        return const Color(0xFFF59E0B); // Amber
      case '55plus':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  String _getLocalizedAgeGroup(String ageGroup, AppLocalizations l10n) {
    switch (ageGroup) {
      case 'under18':
        return l10n.localeName == 'tr'
            ? '18 yaş altı'
            : l10n.localeName == 'ru'
                ? 'Младше 18'
                : 'Under 18';
      case '18-24':
        return '18-24';
      case '25-34':
        return '25-34';
      case '35-44':
        return '35-44';
      case '45-54':
        return '45-54';
      case '55plus':
        return '55+';
      default:
        return l10n.localeName == 'tr'
            ? 'Bilinmiyor'
            : l10n.localeName == 'ru'
                ? 'Неизвестно'
                : 'Unknown';
    }
  }

  String _getLocalizedDemographics(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Demografik Veriler'
        : l10n.localeName == 'ru'
            ? 'Демографические данные'
            : 'Demographics';
  }

  String _getLocalizedGender(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Cinsiyet'
        : l10n.localeName == 'ru'
            ? 'Пол'
            : 'Gender';
  }

  String _getLocalizedAge(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Yaş Grupları'
        : l10n.localeName == 'ru'
            ? 'Возрастные группы'
            : 'Age Groups';
  }

  String _getLocalizedMale(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Erkek'
        : l10n.localeName == 'ru'
            ? 'Мужской'
            : 'Male';
  }

  String _getLocalizedFemale(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Kadın'
        : l10n.localeName == 'ru'
            ? 'Женский'
            : 'Female';
  }

  String _getLocalizedOther(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Diğer'
        : l10n.localeName == 'ru'
            ? 'Другое'
            : 'Other';
  }

  String _getLocalizedNoData(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Veri yok'
        : l10n.localeName == 'ru'
            ? 'Нет данных'
            : 'No data';
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

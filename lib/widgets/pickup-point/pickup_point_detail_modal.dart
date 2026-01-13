import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../models/pickup_point.dart';

class PickupPointDetailModal extends StatelessWidget {
  final PickupPoint pickupPoint;
  final bool showSelectButton;

  const PickupPointDetailModal({
    Key? key,
    required this.pickupPoint,
    this.showSelectButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2839) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle Bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: Colors.orange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pickupPoint.name,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                if (pickupPoint.notes != null &&
                                    pickupPoint.notes!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    pickupPoint.notes!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Details Section
                      _buildDetailSection(
                        l10n.pickupPointDetails,
                        [
                          _DetailItem(
                            icon: Icons.place_outlined,
                            title: l10n.address,
                            content: pickupPoint.address,
                            onTap: () => _openInMaps(
                                pickupPoint.latitude, pickupPoint.longitude),
                            actionIcon: Icons.map_outlined,
                          ),
                          _DetailItem(
                            icon: Icons.access_time,
                            title: l10n.operatingHours,
                            content: pickupPoint.operatingHours,
                          ),
                          if (pickupPoint.contactPerson.isNotEmpty)
                            _DetailItem(
                              icon: Icons.person_outline,
                              title: l10n.contactPerson,
                              content: pickupPoint.contactPerson,
                            ),
                          if (pickupPoint.contactPhone.isNotEmpty)
                            _DetailItem(
                              icon: Icons.phone_outlined,
                              title: l10n.phoneNumber,
                              content: pickupPoint.contactPhone,
                              onTap: () =>
                                  _makePhoneCall(pickupPoint.contactPhone),
                              actionIcon: Icons.call_outlined,
                            ),
                        ],
                        isDark,
                      ),

                      const SizedBox(height: 32),

                      // Action Buttons
                      if (showSelectButton)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, false),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade300,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  l10n.cancel,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  l10n.selectThisPoint,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        // Just close button for view mode
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              l10n.close,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailSection(
    String title,
    List<_DetailItem> items,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: !isLast
                      ? Border(
                          bottom: BorderSide(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade200,
                          ),
                        )
                      : null,
                ),
                child: _buildDetailItem(item, isDark),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(_DetailItem item, bool isDark) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(
            item.icon,
            size: 20,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (item.actionIcon != null) ...[
            const SizedBox(width: 8),
            Icon(
              item.actionIcon,
              size: 18,
              color: Colors.orange,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openInMaps(double latitude, double longitude) async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}

class _DetailItem {
  final IconData icon;
  final String title;
  final String content;
  final VoidCallback? onTap;
  final IconData? actionIcon;

  _DetailItem({
    required this.icon,
    required this.title,
    required this.content,
    this.onTap,
    this.actionIcon,
  });
}

import 'package:flutter/material.dart';
import '../../../models/pickup_point.dart';

class PickupPointCard extends StatelessWidget {
  final PickupPoint pickupPoint;
  final VoidCallback onTap;
  final bool isDark;

  const PickupPointCard({
    Key? key,
    required this.pickupPoint,
    required this.onTap,
    required this.isDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2839) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.grey).withOpacity(0.1),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickupPoint.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (pickupPoint.notes != null &&
                          pickupPoint.notes!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          pickupPoint.notes!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Address
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pickupPoint.address,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Contact Person
            if (pickupPoint.contactPerson.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pickupPoint.contactPerson,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Operating Hours
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pickupPoint.operatingHours,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Phone Number (if available)
            if (pickupPoint.contactPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 16,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pickupPoint.contactPhone,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

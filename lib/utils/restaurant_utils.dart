// lib/utils/restaurant_utils.dart

import '../models/restaurant.dart';

/// Returns true if [restaurant] is currently open based on
/// its [workingDays] and [workingHours] fields.
/// Mirrors the web `isRestaurantOpen` utility exactly.
bool isRestaurantOpen(Restaurant restaurant) {
  final workingDays = restaurant.workingDays;
  final workingHours = restaurant.workingHours;

  // No schedule data → assume open
  if (workingDays == null || workingDays.isEmpty) return true;

  final now = DateTime.now();
  // DateTime.weekday: 1 = Monday … 7 = Sunday
  const dayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final todayName = dayNames[now.weekday - 1];

  if (!workingDays.map((d) => d.toLowerCase()).contains(todayName)) {
    return false;
  }

  if (workingHours == null) return true;

  int parseMinutes(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  final openMin = parseMinutes(workingHours.open);
  final closeMin = parseMinutes(workingHours.close);
  final nowMin = now.hour * 60 + now.minute;

  if (closeMin > openMin) {
    // Same-day range  e.g. 08:00 – 22:00
    return nowMin >= openMin && nowMin < closeMin;
  } else {
    // Overnight range  e.g. 22:00 – 02:00
    return nowMin >= openMin || nowMin < closeMin;
  }
}

// lib/utils/restaurant_utils.dart

import 'package:flutter/cupertino.dart';
import '../generated/l10n/app_localizations.dart';
import '../models/food_address.dart';
import '../models/restaurant.dart';
import 'package:timezone/timezone.dart' as tz;

bool isRestaurantOpen(Restaurant restaurant) {
  final workingDays = restaurant.workingDays;
  final workingHours = restaurant.workingHours;

  if (workingDays == null || workingDays.isEmpty) return true;

  // Always evaluate in Cyprus time regardless of user's device timezone
  final nicosia = tz.getLocation('Asia/Nicosia');
  final now = tz.TZDateTime.now(nicosia);

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
  final days = workingDays.map((d) => d.toLowerCase()).toSet();

  if (workingHours == null) return days.contains(todayName);

  int parseMinutes(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  final openMin = parseMinutes(workingHours.open);
  final closeMin = parseMinutes(workingHours.close);
  final nowMin = now.hour * 60 + now.minute;

  if (closeMin > openMin) {
    return days.contains(todayName) && nowMin >= openMin && nowMin < closeMin;
  } else {
    if (nowMin < closeMin) {
      final yesterdayName = dayNames[(now.weekday - 2 + 7) % 7];
      return days.contains(yesterdayName);
    }
    return days.contains(todayName) && nowMin >= openMin;
  }
}

int? getMinOrderPriceForAddress(
  List<Map<String, dynamic>>? minOrderPrices,
  FoodAddress? foodAddress,
) {
  if (foodAddress == null || minOrderPrices == null) return null;
  for (final e in minOrderPrices) {
    if (e['subregion'] == foodAddress.city) {
      return (e['minOrderPrice'] as num?)?.toInt();
    }
  }
  return null;
}

/// Shows a Cupertino alert if the restaurant is currently closed.
/// Returns true if checkout should proceed, false if blocked.
bool checkRestaurantOpenAndAlert(
  BuildContext context, {
  required Restaurant restaurant,
}) {
  if (isRestaurantOpen(restaurant)) return true;

  final loc = AppLocalizations.of(context);
  showCupertinoDialog(
    context: context,
    builder: (_) => CupertinoAlertDialog(
      title: Text(loc.foodRestaurantClosedTitle),
      content: Text(loc.foodRestaurantClosedMessage),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          child: Text(loc.foodMinOrderOk),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
  return false;
}

/// Shows a Cupertino alert if [cartSubtotal] is below [minOrderPrice].
/// Returns true if checkout should proceed, false if blocked.
bool checkMinOrderAndAlert(
  BuildContext context, {
  required int minOrderPrice,
  required double cartSubtotal,
}) {
  if (cartSubtotal >= minOrderPrice) return true;

  final loc = AppLocalizations.of(context);
  showCupertinoDialog(
    context: context,
    builder: (_) => CupertinoAlertDialog(
      title: Text(loc.foodMinOrderNotMet),
      content: Text(loc.foodMinOrderMessage(
        minOrderPrice.toString(),
        cartSubtotal.toStringAsFixed(2),
      )),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          child: Text(loc.foodMinOrderOk),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
  return false;
}

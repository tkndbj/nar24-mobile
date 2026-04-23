import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CourierType — mirrors the TypeScript union "ours" | "theirs"
// ─────────────────────────────────────────────────────────────────────────────

enum CourierType { ours, theirs }

String courierTypeToString(CourierType t) =>
    t == CourierType.ours ? 'ours' : 'theirs';

// ─────────────────────────────────────────────────────────────────────────────
// showCourierChoiceSheet
//
// Shown when a restaurant accepts a pending order. Returns the selected
// CourierType, or null if the restaurant dismissed the sheet.
//
//   final choice = await showCourierChoiceSheet(
//     context: context,
//     restaurantId: shopId,
//   );
//   if (choice != null) {
//     await updateOrderStatusWithCourierType(order.id, choice);
//   }
//
// The shipment fee displayed is read live from the restaurant doc. The
// actual fee applied to the order is snapshotted server-side at the moment
// of acceptance — so this is strictly informational / for transparency.
// ─────────────────────────────────────────────────────────────────────────────

Future<CourierType?> showCourierChoiceSheet({
  required BuildContext context,
  required String restaurantId,
}) {
  return showModalBottomSheet<CourierType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (ctx) => _CourierChoiceSheet(restaurantId: restaurantId),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _CourierChoiceSheet — internal widget
// ─────────────────────────────────────────────────────────────────────────────

class _CourierChoiceSheet extends StatefulWidget {
  final String restaurantId;
  const _CourierChoiceSheet({required this.restaurantId});

  @override
  State<_CourierChoiceSheet> createState() => _CourierChoiceSheetState();
}

class _CourierChoiceSheetState extends State<_CourierChoiceSheet> {
  double? _shipmentFee;
  bool _loadingFee = true;
  // While a choice is being confirmed we block dismiss and other taps.
  // Parent screens call their CF after showCourierChoiceSheet resolves, so
  // we don't actually wait here — but we guard against double-taps.
  CourierType? _submitting;

  @override
  void initState() {
    super.initState();
    _loadShipmentFee();
  }

  Future<void> _loadShipmentFee() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .get();
      if (!mounted) return;
      final data = snap.data();
      setState(() {
        _shipmentFee = (data?['ourShipmentFee'] as num?)?.toDouble() ?? 0;
        _loadingFee = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shipmentFee = 0;
        _loadingFee = false;
      });
    }
  }

  void _choose(CourierType type) {
    if (_submitting != null) return;
    setState(() => _submitting = type);
    Navigator.of(context).pop(type);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;

    return PopScope(
      // Prevent accidental back-button dismiss while submitting — parent CF
      // call is the only race that matters, and it's fast.
      canPop: _submitting == null,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3D3B55)
                      : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title(locale),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(locale),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[400]
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting != null
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded,
                          size: 20,
                          color: isDark
                              ? Colors.grey[400]
                              : const Color(0xFF9CA3AF)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Option 1 — Nar24 Courier
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _OptionCard(
                  type: CourierType.ours,
                  submitting: _submitting,
                  isDark: isDark,
                  locale: locale,
                  shipmentFee: _shipmentFee,
                  loadingFee: _loadingFee,
                  onTap: () => _choose(CourierType.ours),
                ),
              ),

              const SizedBox(height: 10),

              // Option 2 — Own courier
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _OptionCard(
                  type: CourierType.theirs,
                  submitting: _submitting,
                  isDark: isDark,
                  locale: locale,
                  shipmentFee: _shipmentFee,
                  loadingFee: _loadingFee,
                  onTap: () => _choose(CourierType.theirs),
                ),
              ),

              // Info note
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFEF3C7)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: Color(0xFFB45309)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _note(locale),
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.45,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Cancel
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _submitting != null
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      _cancel(locale),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.grey[400] : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Localized strings (exact parity with Next.js) ──────────────────────

  String _title(String locale) {
    switch (locale) {
      case 'tr':
        return 'Kurye Seçimi';
      case 'ru':
        return 'Выбор курьера';
      default:
        return 'Courier Choice';
    }
  }

  String _subtitle(String locale) {
    switch (locale) {
      case 'tr':
        return 'Bu siparişin teslimatını kim yapacak?';
      case 'ru':
        return 'Кто будет доставлять этот заказ?';
      default:
        return 'Who will deliver this order?';
    }
  }

  String _note(String locale) {
    switch (locale) {
      case 'tr':
        return 'Bu karar siparişe kilitlenir. Kendi kuryemi seçip sonra '
            'fikrinizi değiştirirseniz, kurye çağrı butonundan Nar24\'e '
            'geçebilirsiniz.';
      case 'ru':
        return 'Этот выбор фиксируется за заказом. Если вы выберете '
            'собственного курьера и передумаете, вы сможете переключиться '
            'на Nar24 через кнопку вызова курьера.';
      default:
        return 'This choice is locked once made. If you pick your own '
            'courier and later change your mind, you can switch to Nar24 '
            'from the call-courier button.';
    }
  }

  String _cancel(String locale) {
    switch (locale) {
      case 'tr':
        return 'İptal';
      case 'ru':
        return 'Отмена';
      default:
        return 'Cancel';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OptionCard — one of the two large tappable options
// ─────────────────────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final CourierType type;
  final CourierType? submitting;
  final bool isDark;
  final String locale;
  final double? shipmentFee;
  final bool loadingFee;
  final VoidCallback onTap;

  const _OptionCard({
    required this.type,
    required this.submitting,
    required this.isDark,
    required this.locale,
    required this.shipmentFee,
    required this.loadingFee,
    required this.onTap,
  });

  bool get _isOurs => type == CourierType.ours;
  bool get _disabled => submitting != null || (_isOurs && loadingFee);
  bool get _isSubmitting => submitting == type;

  @override
  Widget build(BuildContext context) {
    // Emerald for ours, blue for theirs (mirrors Next.js).
    final accentBg =
        _isOurs ? const Color(0xFFF0FDFA) : const Color(0xFFEFF6FF);
    final accentFg =
        _isOurs ? const Color(0xFF0D9488) : const Color(0xFF2563EB);
    final accentBorder =
        _isOurs ? const Color(0xFF14B8A6) : const Color(0xFF3B82F6);

    return AnimatedOpacity(
      opacity: _disabled && !_isSubmitting ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isSubmitting
                    ? accentBorder
                    : (isDark
                        ? const Color(0xFF2D2B42)
                        : const Color(0xFFE5E7EB)),
                width: 2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isSubmitting
                      ? Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(accentFg),
                            ),
                          ),
                        )
                      : Icon(
                          _isOurs
                              ? Icons.delivery_dining_rounded
                              : Icons.storefront_rounded,
                          color: accentFg,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),

                // Text block
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _optionLabel(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111827),
                            ),
                          ),
                          if (_isOurs && !loadingFee && shipmentFee != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCCFBF1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${shipmentFee!.toStringAsFixed(0)} TL',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _optionDescription(),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: isDark
                              ? Colors.grey[400]
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Localized strings (exact parity with Next.js) ──────────────────────

  String _optionLabel() {
    if (_isOurs) {
      switch (locale) {
        case 'tr':
          return 'Nar24 Kuryesi';
        case 'ru':
          return 'Курьер Nar24';
        default:
          return 'Nar24 Courier';
      }
    }
    switch (locale) {
      case 'tr':
        return 'Kendi Kuryem';
      case 'ru':
        return 'Собственный курьер';
      default:
        return 'Our Own Courier';
    }
  }

  String _optionDescription() {
    if (_isOurs) {
      if (loadingFee) {
        switch (locale) {
          case 'tr':
            return 'Ücret yükleniyor...';
          case 'ru':
            return 'Загрузка стоимости...';
          default:
            return 'Loading fee...';
        }
      }
      final fee = (shipmentFee ?? 0).toStringAsFixed(0);
      switch (locale) {
        case 'tr':
          return 'Bu siparişin teslimatını Nar24 sağlayacaktır. Teslimat '
              'ücreti $fee TL\'dir ve restoran tarafından karşılanır.';
        case 'ru':
          return 'Nar24 выполнит доставку этого заказа. Стоимость доставки '
              '$fee TL оплачивается рестораном.';
        default:
          return 'Nar24 will handle delivery for this order. A shipment '
              'fee of $fee TL applies and is covered by the restaurant.';
      }
    }
    switch (locale) {
      case 'tr':
        return 'Bu siparişin teslimatını kendi kuryeniz yapacak. Nar24 '
            'teslimat ücreti uygulanmaz.';
      case 'ru':
        return 'Ваш собственный курьер выполнит доставку этого заказа. '
            'Стоимость доставки Nar24 не взимается.';
      default:
        return 'Your own courier will deliver this order. No Nar24 '
            'shipment fee applies.';
    }
  }
}

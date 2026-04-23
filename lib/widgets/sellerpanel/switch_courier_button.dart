import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// Flutter equivalent of the Next.js `SwitchCourierButton`.
///
/// Flips a `theirs` food order to `ours` via the `switchFoodOrderCourier` CF.
/// The caller is responsible for only rendering this when:
///   - order.courierType == 'theirs'
///   - order.status ∈ {'accepted', 'ready'}
///
/// Shows a confirm dialog before firing the CF because the action is one-way.
class SwitchCourierButton extends StatefulWidget {
  final String orderId;
  final String locale;
  final VoidCallback? onSuccess;

  /// 'compact' → small violet pill suitable for order-card action rows.
  /// 'full'    → larger button suitable for expanded order detail rows.
  final String variant;

  const SwitchCourierButton({
    Key? key,
    required this.orderId,
    required this.locale,
    this.variant = 'compact',
    this.onSuccess,
  }) : super(key: key);

  @override
  State<SwitchCourierButton> createState() => _SwitchCourierButtonState();
}

class _SwitchCourierButtonState extends State<SwitchCourierButton> {
  bool _busy = false;

  Future<bool> _confirm(BuildContext context) async {
    final locale = widget.locale;
    final title = locale == 'tr'
        ? 'Nar24 Kuryesine Aktar'
        : (locale == 'ru'
            ? 'Передать курьеру Nar24'
            : 'Switch to Nar24 Courier');
    final body = locale == 'tr'
        ? 'Bu siparişi Nar24 kuryesine aktarmak istediğinize emin misiniz? Kargo ücreti hesabınızdan kesilecektir.'
        : (locale == 'ru'
            ? 'Передать этот заказ курьеру Nar24? Стоимость доставки будет удержана с вашего счёта.'
            : 'Switch this order to a Nar24 courier? The shipment fee will be deducted from your payout.');
    final confirmText = locale == 'tr'
        ? 'Onayla'
        : (locale == 'ru' ? 'Подтвердить' : 'Confirm');
    final cancelText =
        locale == 'tr' ? 'İptal' : (locale == 'ru' ? 'Отмена' : 'Cancel');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    final confirmed = await _confirm(context);
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('switchFoodOrderCourier')
          .call({'orderId': widget.orderId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          widget.locale == 'tr'
              ? 'Sipariş Nar24 kuryesine aktarıldı'
              : (widget.locale == 'ru'
                  ? 'Заказ передан курьеру Nar24'
                  : 'Order switched to Nar24 courier'),
        ),
        backgroundColor: const Color(0xFF7C3AED),
        behavior: SnackBarBehavior.floating,
      ));
      widget.onSuccess?.call();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.message ??
              (widget.locale == 'tr'
                  ? 'Aktarım başarısız'
                  : (widget.locale == 'ru'
                      ? 'Не удалось передать'
                      : 'Failed to switch courier')),
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          widget.locale == 'tr'
              ? 'Aktarım başarısız'
              : (widget.locale == 'ru'
                  ? 'Не удалось передать'
                  : 'Failed to switch courier'),
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.locale == 'tr'
        ? 'Nar24 Kuryesine Geç'
        : (widget.locale == 'ru' ? 'Курьер Nar24' : 'Switch to Nar24');

    final isFull = widget.variant == 'full';

    return GestureDetector(
      onTap: _busy ? null : _handleTap,
      child: AnimatedOpacity(
        opacity: _busy ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isFull ? 12 : 10,
            vertical: isFull ? 10 : 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _busy
                ? [
                    SizedBox(
                      width: isFull ? 14 : 12,
                      height: isFull ? 14 : 12,
                      child: const CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ]
                : [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: isFull ? 14 : 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isFull ? 12 : 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

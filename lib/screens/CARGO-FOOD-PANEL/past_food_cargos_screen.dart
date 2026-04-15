// lib/screens/CARGO-FOOD-PANEL/past_food_cargos_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../generated/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PAST ENTRY — wraps a doc with its source collection
// ─────────────────────────────────────────────────────────────────────────────

class _PastEntry {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String collection; // 'orders-food' | 'orders-market'
  final Timestamp assignedAt;

  const _PastEntry(this.doc, this.collection, this.assignedAt);
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class PastFoodCargosScreen extends StatefulWidget {
  const PastFoodCargosScreen({super.key});

  @override
  State<PastFoodCargosScreen> createState() => _PastFoodCargosScreenState();
}

class _PastFoodCargosScreenState extends State<PastFoodCargosScreen> {
  static const _pageSize = 10;

  final _firestore = FirebaseFirestore.instance;

  // Per-collection pagination state
  final List<_PastEntry> _foodBuffer = [];
  final List<_PastEntry> _marketBuffer = [];
  DocumentSnapshot? _foodCursor;
  DocumentSnapshot? _marketCursor;
  bool _foodExhausted = false;
  bool _marketExhausted = false;

  // Items already released to the UI (ordered newest-first)
  final List<_PastEntry> _displayed = [];

  bool _loading = false;
  bool _initialLoad = true;

  bool get _hasMore =>
      !_foodExhausted ||
      !_marketExhausted ||
      _foodBuffer.isNotEmpty ||
      _marketBuffer.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _fetchPage();
  }

  Query<Map<String, dynamic>> _baseQuery(String collection, String uid) {
    return _firestore
        .collection(collection)
        .where('cargoUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'delivered')
        .orderBy('assignedAt', descending: true)
        .limit(_pageSize);
  }

  Future<void> _fetchCollectionPage(
    String collection,
    String uid,
    List<_PastEntry> buffer,
    DocumentSnapshot? cursor,
    void Function(DocumentSnapshot? newCursor, bool exhausted) onDone,
  ) async {
    var query = _baseQuery(collection, uid);
    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    final snap = await query.get();
    for (final d in snap.docs) {
      final ts = d.data()['assignedAt'] as Timestamp?;
      if (ts == null) continue; // skip docs without sort key
      buffer.add(_PastEntry(d, collection, ts));
    }
    onDone(
      snap.docs.isNotEmpty ? snap.docs.last : cursor,
      snap.docs.length < _pageSize,
    );
  }

  Future<void> _fetchPage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _loading) return;

    setState(() => _loading = true);

    try {
      // Refill whichever buffer is empty — run in parallel when both need it.
      final refills = <Future<void>>[];
      if (_foodBuffer.isEmpty && !_foodExhausted) {
        refills.add(_fetchCollectionPage(
          'orders-food',
          user.uid,
          _foodBuffer,
          _foodCursor,
          (newCursor, exhausted) {
            _foodCursor = newCursor;
            _foodExhausted = exhausted;
          },
        ));
      }
      if (_marketBuffer.isEmpty && !_marketExhausted) {
        refills.add(_fetchCollectionPage(
          'orders-market',
          user.uid,
          _marketBuffer,
          _marketCursor,
          (newCursor, exhausted) {
            _marketCursor = newCursor;
            _marketExhausted = exhausted;
          },
        ));
      }
      await Future.wait(refills);

      // Watermark cutoff: we can safely release items whose assignedAt is
      // newer than OR equal to the older of the two buffer tails, because
      // neither collection can still produce items above that cutoff.
      // If a collection is exhausted, it has no influence on the cutoff.
      Timestamp? cutoff;
      if (!_foodExhausted && _foodBuffer.isNotEmpty) {
        cutoff = _foodBuffer.last.assignedAt;
      }
      if (!_marketExhausted && _marketBuffer.isNotEmpty) {
        final mTail = _marketBuffer.last.assignedAt;
        if (cutoff == null || mTail.compareTo(cutoff) > 0) {
          cutoff = mTail;
        }
      }

      // Drain items >= cutoff from both buffers (null cutoff = drain all)
      final released = <_PastEntry>[];
      _drainBuffer(_foodBuffer, cutoff, released);
      _drainBuffer(_marketBuffer, cutoff, released);
      released.sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

      setState(() {
        _displayed.addAll(released);
        _initialLoad = false;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _initialLoad = false;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _drainBuffer(
    List<_PastEntry> buffer,
    Timestamp? cutoff,
    List<_PastEntry> out,
  ) {
    while (buffer.isNotEmpty) {
      if (cutoff != null && buffer.first.assignedAt.compareTo(cutoff) < 0) {
        break;
      }
      out.add(buffer.removeAt(0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          loc.pastFoodCargosTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(isDark, loc),
    );
  }

  Widget _buildBody(bool isDark, AppLocalizations loc) {
    if (_initialLoad && _loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2.5),
      );
    }

    if (_displayed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📋', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                loc.pastFoodCargosEmpty,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                loc.pastFoodCargosEmptySub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _displayed.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _displayed.length) {
          return _LoadMoreButton(
            loading: _loading,
            onPressed: _fetchPage,
            loc: loc,
          );
        }
        final entry = _displayed[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _PastOrderCard(
            data: entry.doc.data(),
            orderId: entry.doc.id,
            collection: entry.collection,
            isDark: isDark,
            loc: loc,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOAD MORE BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  final AppLocalizations loc;

  const _LoadMoreButton({
    required this.loading,
    required this.onPressed,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.orange, strokeWidth: 2),
                  )
                : Text(
                    loc.pastFoodCargosLoadMore,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAST ORDER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PastOrderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String orderId;
  final String collection;
  final bool isDark;
  final AppLocalizations loc;

  const _PastOrderCard({
    required this.data,
    required this.orderId,
    required this.collection,
    required this.isDark,
    required this.loc,
  });

  bool get _isMarket => collection == 'orders-market';

  String get _pickupName {
    if (_isMarket) return (data['marketName'] as String?) ?? 'Market';
    return (data['restaurantName'] as String?) ?? '—';
  }

  String? get _pickupImage {
    if (_isMarket) return null;
    return data['restaurantProfileImage'] as String?;
  }

  String get _addressLine {
    final addr = data['deliveryAddress'] as Map<String, dynamic>?;
    if (addr == null) return '—';
    return [
      addr['addressLine1'] as String? ?? '',
      addr['addressLine2'] as String? ?? '',
      addr['city'] as String? ?? '',
    ].where((s) => s.isNotEmpty).join(', ');
  }

  String _itemsSummary(int count) {
    final items = data['items'] as List<dynamic>? ?? const [];
    if (items.isEmpty) return loc.foodCargoItemCount(count);
    final parts = items.take(2).map((raw) {
      final item = raw as Map<String, dynamic>;
      final name = item['name'] as String? ?? '';
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      return qty > 1 ? '$name x$qty' : name;
    }).join(', ');
    final overflow = items.length > 2 ? ' +${items.length - 2}' : '';
    return '$parts$overflow';
  }

  String _formatDeliveredAt() {
    // Prefer deliveredAt if it exists, fall back to updatedAt (courier_actions
    // trigger stamps updatedAt when flipping to 'delivered').
    final ts = data['deliveredAt'] ?? data['updatedAt'];
    if (ts == null) return '';
    final dt = (ts as Timestamp).toDate();
    final formatted = DateFormat('dd MMM yyyy, HH:mm').format(dt);
    return loc.pastFoodCargosDeliveredAt(formatted);
  }

  @override
  Widget build(BuildContext context) {
    final pickupName = _pickupName;
    final pickupImage = _pickupImage;
    final buyerName = data['buyerName'] as String? ?? '—';
    final totalPrice = (data['totalPrice'] as num?)?.toDouble() ?? 0;
    final currency = data['currency'] as String? ?? 'TL';
    final isPaid = data['isPaid'] as bool? ?? false;
    final items = data['items'] as List<dynamic>? ?? const [];
    final itemCount = (data['itemCount'] as num?)?.toInt() ?? items.length;
    final shortId = orderId.substring(0, 8).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: isDark
                        ? const Color(0xFF2D2B3F)
                        : (_isMarket ? Colors.indigo[50] : Colors.orange[50]),
                    child: pickupImage != null && pickupImage.isNotEmpty
                        ? Image.network(
                            pickupImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                _isMarket ? '🛒' : '🍽️',
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              _isMarket ? '🛒' : '🍽️',
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              pickupName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isMarket) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'MARKET',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${loc.foodCargoOrderId} #$shortId',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                // Delivered badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.green.withOpacity(0.13)
                        : Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: isDark ? Colors.green[400] : Colors.green[700],
                  ),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark ? const Color(0xFF2D2B3F) : const Color(0xFFE5E7EB),
          ),

          // ── Info rows ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.person_rounded,
                  label: loc.foodCargoCustomer,
                  value: buyerName,
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: _isMarket
                      ? Icons.shopping_bag_rounded
                      : Icons.fastfood_rounded,
                  label: loc.foodCargoItems,
                  value: _itemsSummary(itemCount),
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.location_on_rounded,
                  label: loc.foodCargoAddressLabel,
                  value: _addressLine,
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.receipt_rounded,
                  label: loc.foodCargoTotalLabel,
                  value:
                      '${totalPrice.toStringAsFixed(0)} $currency  ·  ${isPaid ? loc.foodCargoPaid : loc.foodCargoPaymentAtDoor}',
                  isDark: isDark,
                  valueColor: isPaid
                      ? (isDark ? Colors.green[400] : Colors.green[700])
                      : (isDark ? Colors.orange[300] : Colors.orange[700]),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.schedule_rounded,
                  label: '',
                  value: _formatDeliveredAt(),
                  isDark: isDark,
                  valueColor: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO ROW (reused from food_cargo_screen pattern)
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 15,
            color: isDark ? Colors.grey[500] : Colors.grey[400],
          ),
        ),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          SizedBox(
            width: 78,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color:
                  valueColor ?? (isDark ? Colors.grey[200] : Colors.grey[800]),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared, zero-allocation-where-possible parsing helpers.
///
/// Every `fromDocument`, `fromJson`, and `fromSearchHit` factory was
/// re-declaring the same closures on every call. Moving them here:
///   • eliminates per-call closure allocation
///   • gives a single place to fix edge-case parsing bugs
///   • makes unit-testing trivial
abstract final class Parse {
  // ── Scalars ──────────────────────────────────────────────────────────────

  static double toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static int toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String toStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    return v.toString();
  }

  static String? toStrNullable(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool toBool(dynamic v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    return v == true;
  }

  // ── Lists ────────────────────────────────────────────────────────────────

  static List<String> toStringList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return List<String>.unmodifiable(v.map((e) => e.toString()));
    if (v is String) return v.isEmpty ? const [] : List<String>.unmodifiable([v]);
    return const [];
  }

  // ── Maps ─────────────────────────────────────────────────────────────────

  static Map<String, int> toColorQty(dynamic v) {
    if (v is! Map) return const {};
    final m = <String, int>{};
    v.forEach((k, val) => m[k.toString()] = toInt(val));
    return Map<String, int>.unmodifiable(m);
  }

  static Map<String, List<String>> toColorImages(dynamic v) {
    if (v is! Map) return const {};
    final m = <String, List<String>>{};
    v.forEach((k, val) {
      if (val is List) {
        m[k.toString()] = List<String>.unmodifiable(
          val.map((e) => e.toString()),
        );
      } else if (val is String && val.isNotEmpty) {
        m[k.toString()] = List<String>.unmodifiable([val]);
      }
    });
    return Map<String, List<String>>.unmodifiable(m);
  }

  static Map<String, dynamic> toAttributes(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    return const {};
  }

  static List<Map<String, dynamic>>? toBundleData(dynamic v) {
    if (v == null || v is! List) return null;
    try {
      return List<Map<String, dynamic>>.unmodifiable(
        v.map((item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return Map<String, dynamic>.from(item);
          return <String, dynamic>{};
        }),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Timestamps ───────────────────────────────────────────────────────────

  static Timestamp toTimestamp(dynamic v) {
    if (v is Timestamp) return v;
    if (v is int) return Timestamp.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return Timestamp.fromDate(DateTime.parse(v));
      } catch (_) {}
    }
    return Timestamp.now();
  }

  static Timestamp? toTimestampNullable(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v;
    if (v is int) return Timestamp.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return Timestamp.fromDate(DateTime.parse(v));
      } catch (_) {}
    }
    return null;
  }

  // ── Source collection detection ──────────────────────────────────────────

  static String? sourceCollectionFromRef(DocumentReference ref) {
    final path = ref.path;
    if (path.startsWith('products/')) return 'products';
    if (path.startsWith('shop_products/')) return 'shop_products';
    return null;
  }

  static String sourceCollectionFromJson(Map<String, dynamic> json) {
    final explicit = json['sourceCollection'] as String?;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return (json['shopId'] != null && json['shopId'].toString().isNotEmpty)
        ? 'shop_products'
        : 'products';
  }
}
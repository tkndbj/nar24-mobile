import '../constants/all_in_one_category_data.dart';

class BuyerSubSubcategory {
  final String key;
  final Map<String, String> labels;

  BuyerSubSubcategory({required this.key, required this.labels});

  factory BuyerSubSubcategory.fromJson(dynamic json) {
    // Support both old format (plain string) and new format (object with labels)
    if (json is String) {
      return BuyerSubSubcategory(
        key: json,
        labels: {'en': json, 'tr': json, 'ru': json},
      );
    }
    final map = json as Map<String, dynamic>;
    return BuyerSubSubcategory(
      key: map['key'] as String,
      labels: Map<String, String>.from(map['labels'] as Map? ?? {}),
    );
  }

  String getLabel(String languageCode) {
    return labels[languageCode] ?? labels['en'] ?? key;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'labels': labels,
      };
}

class BuyerSubcategory {
  final String key;
  final Map<String, String> labels;
  final List<BuyerSubSubcategory> subSubcategories;

  BuyerSubcategory({
    required this.key,
    required this.labels,
    required this.subSubcategories,
  });

  factory BuyerSubcategory.fromJson(Map<String, dynamic> json) =>
      BuyerSubcategory(
        key: json['key'] as String,
        labels: Map<String, String>.from(json['labels'] as Map? ?? {}),
        subSubcategories: (json['subSubcategories'] as List? ?? [])
            .map((s) => BuyerSubSubcategory.fromJson(s))
            .toList(),
      );

  String getLabel(String languageCode) {
    return labels[languageCode] ?? labels['en'] ?? key;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'labels': labels,
        'subSubcategories': subSubcategories.map((s) => s.toJson()).toList(),
      };
}

class BuyerCategory {
  final String key;
  final String image;
  final Map<String, String> labels;
  final List<BuyerSubcategory> subcategories;

  BuyerCategory({
    required this.key,
    required this.image,
    required this.labels,
    required this.subcategories,
  });

  factory BuyerCategory.fromJson(Map<String, dynamic> json) => BuyerCategory(
        key: json['key'] as String,
        image: (json['image'] as String?) ?? '',
        labels: Map<String, String>.from(json['labels'] as Map? ?? {}),
        subcategories: (json['subcategories'] as List? ?? [])
            .map((s) => BuyerSubcategory.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  String getLabel(String languageCode) {
    return labels[languageCode] ?? labels['en'] ?? key;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'image': image,
        'labels': labels,
        'subcategories': subcategories.map((s) => s.toJson()).toList(),
      };
}

class CategoryStructure {
  final List<BuyerCategory> buyerCategories;
  final Map<String, Map<String, String>> buyerToProductMapping;

  CategoryStructure({
    required this.buyerCategories,
    required this.buyerToProductMapping,
  });

  factory CategoryStructure.fromJson(Map<String, dynamic> json) {
    return CategoryStructure(
      buyerCategories: (json['buyerCategories'] as List? ?? [])
          .map((c) => BuyerCategory.fromJson(c as Map<String, dynamic>))
          .toList(),
      buyerToProductMapping:
          (json['buyerToProductMapping'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, Map<String, String>.from(v as Map)),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  List<Map<String, String>> get kBuyerCategories =>
      buyerCategories.map((c) => {'key': c.key, 'image': c.image}).toList();

  List<BuyerSubcategory> getSubcategories(String buyerCategory) {
    return buyerCategories
        .firstWhere(
          (c) => c.key == buyerCategory,
          orElse: () =>
              BuyerCategory(key: '', image: '', labels: {}, subcategories: []),
        )
        .subcategories;
  }

  List<BuyerSubSubcategory> getSubSubcategories(
    String buyerCategory,
    String subcategory,
  ) {
    final cat = buyerCategories.firstWhere(
      (c) => c.key == buyerCategory,
      orElse: () =>
          BuyerCategory(key: '', image: '', labels: {}, subcategories: []),
    );
    return cat.subcategories
        .firstWhere(
          (s) => s.key == subcategory,
          orElse: () =>
              BuyerSubcategory(key: '', labels: {}, subSubcategories: []),
        )
        .subSubcategories;
  }

  Map<String, String?> getBuyerToProductMapping(
    String buyerCategory,
    String? buyerSubcategory,
    String? buyerSubSubcategory,
  ) {
    final String? productCategory;
    if (buyerSubcategory != null) {
      final categoryMap = buyerToProductMapping[buyerCategory];
      productCategory =
          categoryMap != null ? categoryMap[buyerSubcategory] : null;
    } else {
      productCategory = null;
    }

    final String? productSubcategory =
        (buyerCategory == 'Women' || buyerCategory == 'Men')
            ? buyerSubSubcategory
            : buyerSubcategory;

    return {
      'category': productCategory,
      'subcategory': productSubcategory,
      'subSubcategory': null,
    };
  }

  // Bundled fallback
  factory CategoryStructure.defaults() {
    return CategoryStructure.fromJson(AllInOneCategoryData.toJson());
  }
}

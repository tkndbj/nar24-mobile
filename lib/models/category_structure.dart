import '../constants/all_in_one_category_data.dart';

class BuyerSubcategory {
  final String key;
  final List<String> subSubcategories;

  BuyerSubcategory({required this.key, required this.subSubcategories});

  factory BuyerSubcategory.fromJson(Map<String, dynamic> json) =>
      BuyerSubcategory(
        key: json['key'] as String,
        subSubcategories: List<String>.from(json['subSubcategories'] ?? []),
      );
}

class BuyerCategory {
  final String key;
  final String image;
  final List<BuyerSubcategory> subcategories;

  BuyerCategory({
    required this.key,
    required this.image,
    required this.subcategories,
  });

  factory BuyerCategory.fromJson(Map<String, dynamic> json) => BuyerCategory(
        key: json['key'] as String,
        image: (json['image'] as String?) ?? '',
        subcategories: (json['subcategories'] as List? ?? [])
            .map((s) => BuyerSubcategory.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
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
        (k, v) => MapEntry(
          k,
          Map<String, String>.from(v as Map),
        ),
      ),
    );
  }

  // ── Helpers matching your old AllInOneCategoryData API ──────────────────

  List<Map<String, String>> get kBuyerCategories => buyerCategories
      .map((c) => {'key': c.key, 'image': c.image})
      .toList();

  List<String> getSubcategories(String buyerCategory) {
    return buyerCategories
        .firstWhere((c) => c.key == buyerCategory,
            orElse: () => BuyerCategory(key: '', image: '', subcategories: []))
        .subcategories
        .map((s) => s.key)
        .toList();
  }

  List<String> getSubSubcategories(String buyerCategory, String subcategory) {
    final cat = buyerCategories.firstWhere(
      (c) => c.key == buyerCategory,
      orElse: () => BuyerCategory(key: '', image: '', subcategories: []),
    );
    return cat.subcategories
        .firstWhere(
          (s) => s.key == subcategory,
          orElse: () => BuyerSubcategory(key: '', subSubcategories: []),
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
    productCategory = categoryMap != null ? categoryMap[buyerSubcategory] : null;
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

  // Bundled fallback — mirrors your current static data
  factory CategoryStructure.defaults() {
    return CategoryStructure.fromJson(
      AllInOneCategoryData.toJson(), // see Step 2 below
    );
  }
}
// lib/models/shop_suggestion.dart

class ShopSuggestion {
  final String id;
  final String name;
  final String? profileImageUrl;
  final List<String> categories;
  final double? relevanceScore;

  ShopSuggestion({
    required this.id,
    required this.name,
    this.profileImageUrl,
    required this.categories,
    this.relevanceScore,
  });

  factory ShopSuggestion.fromSearchHit(Map<String, dynamic> hit) {
    String shopId = hit['id']?.toString() ?? '';
    if (shopId.startsWith('shops_')) {
      shopId = shopId.substring('shops_'.length);
    }

    return ShopSuggestion(
      id: shopId,
      name: hit['name'] ?? '',
      profileImageUrl: hit['profileImageUrl'],
      categories: List<String>.from(hit['categories'] ?? []),
      relevanceScore: hit['_rankingInfo']?['matchedGeoLocation']?['distance']?.toDouble(),
    );
  }

  // Helper method to check if shop matches a category
  bool hasCategory(String category) {
    return categories.any((c) => 
      c.toLowerCase().contains(category.toLowerCase()) ||
      category.toLowerCase().contains(c.toLowerCase())
    );
  }

  // Helper method to get a display-friendly category list
  String get categoriesDisplay {
    if (categories.isEmpty) return '';
    if (categories.length <= 2) return categories.join(' • ');
    return '${categories.take(2).join(' • ')} +${categories.length - 2}';
  }
}
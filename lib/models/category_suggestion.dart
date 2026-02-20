// lib/models/category_suggestion.dart - Updated version

class CategorySuggestion {
  final String categoryKey;
  final String? subcategoryKey;
  final String? subsubcategoryKey;
  final String displayName;
  final int level; // 0 = main category, 1 = subcategory, 2 = sub-subcategory
  final String language;
  final List<String>? matchedKeywords; // For enhanced scoring
  
  const CategorySuggestion({
    required this.categoryKey,
    this.subcategoryKey,
    this.subsubcategoryKey,
    required this.displayName,
    required this.level,
    required this.language,
    this.matchedKeywords,
  });

  factory CategorySuggestion.fromSearchHit(Map<String, dynamic> hit) {
    return CategorySuggestion(
      categoryKey: hit['categoryKey'] ?? '',
      subcategoryKey: hit['subcategoryKey'],
      subsubcategoryKey: hit['subsubcategoryKey'],
      displayName: hit['displayName'] ?? hit['name'] ?? '',
      level: hit['level'] ?? 0,
      language: hit['language'] ?? hit['languageCode'] ?? 'en',
      matchedKeywords: hit['matchedKeywords']?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categoryKey': categoryKey,
      'subcategoryKey': subcategoryKey,
      'subsubcategoryKey': subsubcategoryKey,
      'displayName': displayName,
      'level': level,
      'language': language,
      'matchedKeywords': matchedKeywords,
    };
  }

  @override
  String toString() {
    return 'CategorySuggestion(categoryKey: $categoryKey, subcategoryKey: $subcategoryKey, subsubcategoryKey: $subsubcategoryKey, displayName: $displayName, level: $level, language: $language)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CategorySuggestion &&
        other.categoryKey == categoryKey &&
        other.subcategoryKey == subcategoryKey &&
        other.subsubcategoryKey == subsubcategoryKey &&
        other.displayName == displayName &&
        other.level == level &&
        other.language == language;
  }

  @override
  int get hashCode {
    return categoryKey.hashCode ^
        subcategoryKey.hashCode ^
        subsubcategoryKey.hashCode ^
        displayName.hashCode ^
        level.hashCode ^
        language.hashCode;
  }

  /// Create a copy with optional parameter overrides
  CategorySuggestion copyWith({
    String? categoryKey,
    String? subcategoryKey,
    String? subsubcategoryKey,
    String? displayName,
    int? level,
    String? language,
    List<String>? matchedKeywords,
  }) {
    return CategorySuggestion(
      categoryKey: categoryKey ?? this.categoryKey,
      subcategoryKey: subcategoryKey ?? this.subcategoryKey,
      subsubcategoryKey: subsubcategoryKey ?? this.subsubcategoryKey,
      displayName: displayName ?? this.displayName,
      level: level ?? this.level,
      language: language ?? this.language,
      matchedKeywords: matchedKeywords ?? this.matchedKeywords,
    );
  }

  /// Get a simplified display name for the UI
  String get simpleDisplayName {
    final parts = displayName.split(' > ');
    return parts.last.trim();
  }

  /// Get breadcrumb path for nested categories
  String get breadcrumb {
    final parts = displayName.split(' > ');
    if (parts.length > 1) {
      return parts.take(parts.length - 1).join(' • ');
    }
    return '';
  }

  /// Check if this is a main category (level 0)
  bool get isMainCategory => level == 0;

  /// Check if this is a subcategory (level 1)
  bool get isSubcategory => level == 1;

  /// Check if this is a sub-subcategory (level 2)
  bool get isSubSubcategory => level == 2;
}
// lib/services/enhanced_category_search.dart
import 'package:flutter/foundation.dart';
import '../models/category_suggestion.dart';

class CategorySearchScorer {
  /// Calculate relevance score for a category suggestion
  static double calculateRelevanceScore(
    CategorySuggestion suggestion, 
    String searchQuery
  ) {
    final query = searchQuery.toLowerCase().trim();
    final displayName = suggestion.displayName.toLowerCase();
    final categoryKey = suggestion.categoryKey.toLowerCase();
    final subcategoryKey = suggestion.subcategoryKey?.toLowerCase() ?? '';
    final subsubcategoryKey = suggestion.subsubcategoryKey?.toLowerCase() ?? '';
    
    double score = 0.0;
    
    // 1. Exact matches (highest priority)
    if (displayName == query) score += 100.0;
    if (categoryKey == query) score += 90.0;
    if (subcategoryKey == query) score += 80.0;
    if (subsubcategoryKey == query) score += 70.0;
    
    // 2. Starts with matches (high priority)
    if (displayName.startsWith(query)) score += 50.0;
    if (categoryKey.startsWith(query)) score += 45.0;
    if (subcategoryKey.startsWith(query)) score += 40.0;
    if (subsubcategoryKey.startsWith(query)) score += 35.0;
    
    // 3. Contains matches (medium priority)
    if (displayName.contains(query)) score += 25.0;
    if (categoryKey.contains(query)) score += 20.0;
    if (subcategoryKey.contains(query)) score += 15.0;
    if (subsubcategoryKey.contains(query)) score += 10.0;
    
    // 4. Word-by-word matching (for multi-word queries)
    final queryWords = query.split(' ');
    final displayWords = displayName.split(' ');
    final categoryWords = categoryKey.split(' ');
    
    for (final queryWord in queryWords) {
      if (queryWord.length < 2) continue; // Skip very short words
      
      // Check display name words
      for (final displayWord in displayWords) {
        if (displayWord == queryWord) score += 15.0;
        else if (displayWord.startsWith(queryWord)) score += 10.0;
        else if (displayWord.contains(queryWord)) score += 5.0;
      }
      
      // Check category words
      for (final categoryWord in categoryWords) {
        if (categoryWord == queryWord) score += 12.0;
        else if (categoryWord.startsWith(queryWord)) score += 8.0;
        else if (categoryWord.contains(queryWord)) score += 4.0;
      }
    }
    
    // 5. Level penalty (prefer higher-level categories for broader searches)
    switch (suggestion.level) {
      case 0: score += 5.0; // Main categories
      case 1: score += 3.0; // Subcategories
      case 2: score += 1.0; // Sub-subcategories
    }
    
    // 6. Fuzzy matching bonus for similar words
    score += _calculateFuzzyScore(query, displayName) * 10.0;
    score += _calculateFuzzyScore(query, categoryKey) * 8.0;
    
    // 7. Keyword matching from Algolia search relevance
    if (suggestion.matchedKeywords?.isNotEmpty == true) {
      score += suggestion.matchedKeywords!.length * 2.0;
    }
    
    return score;
  }
  
  /// Simple fuzzy matching using Levenshtein distance
  static double _calculateFuzzyScore(String query, String target) {
    if (query.isEmpty || target.isEmpty) return 0.0;
    
    final distance = _levenshteinDistance(query, target);
    final maxLength = [query.length, target.length].reduce((a, b) => a > b ? a : b);
    
    // Return similarity ratio (0.0 to 1.0)
    return 1.0 - (distance / maxLength);
  }
  
  /// Calculate Levenshtein distance between two strings
  static int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    
    List<List<int>> matrix = List.generate(
      s1.length + 1, 
      (i) => List.filled(s2.length + 1, 0)
    );
    
    // Initialize first row and column
    for (int i = 0; i <= s1.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      matrix[0][j] = j;
    }
    
    // Fill the matrix
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    return matrix[s1.length][s2.length];
  }
  
  /// Sort and limit category suggestions by relevance
  static List<CategorySuggestion> sortAndLimitResults(
    List<CategorySuggestion> suggestions,
    String searchQuery, {
    int maxResults = 15,
  }) {
    // Calculate scores for all suggestions
    final scoredSuggestions = suggestions.map((suggestion) => {
      'suggestion': suggestion,
      'score': calculateRelevanceScore(suggestion, searchQuery),
    }).toList();
    
    // Sort by score (descending)
    scoredSuggestions.sort((a, b) => 
      (b['score'] as double).compareTo(a['score'] as double));
    
    // Filter out very low scores (less than 1.0)
    final filteredSuggestions = scoredSuggestions
        .where((item) => (item['score'] as double) > 1.0)
        .take(maxResults)
        .map((item) => item['suggestion'] as CategorySuggestion)
        .toList();
    
    return filteredSuggestions;
  }
  
  /// Debug method to show scores for testing
  static void debugPrintScores(
    List<CategorySuggestion> suggestions,
    String searchQuery
  ) {
    if (kDebugMode) {
      print('\n=== Category Search Debug for "$searchQuery" ===');

      final scoredSuggestions = suggestions.map((suggestion) => {
        'suggestion': suggestion,
        'score': calculateRelevanceScore(suggestion, searchQuery),
      }).toList();

      scoredSuggestions.sort((a, b) =>
        (b['score'] as double).compareTo(a['score'] as double));

      for (int i = 0; i < scoredSuggestions.take(10).length; i++) {
        final item = scoredSuggestions[i];
        final suggestion = item['suggestion'] as CategorySuggestion;
        final score = item['score'] as double;

        print('${i + 1}. ${suggestion.displayName} (${suggestion.level}) - Score: ${score.toStringAsFixed(1)}');
      }
      print('==========================================\n');
    }
  }
}
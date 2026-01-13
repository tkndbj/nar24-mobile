class FirebaseDataCleaner {
  /// Recursively cleans data to ensure Firebase compatibility
  /// Removes null, undefined, empty strings, empty arrays, and empty objects
  static Map<String, dynamic> cleanData(Map<String, dynamic> data) {
    final Map<String, dynamic> cleaned = {};
    
    data.forEach((key, value) {
      final cleanedValue = _cleanValue(value);
      if (_isValidValue(cleanedValue)) {
        cleaned[key] = cleanedValue;
      }
    });
    
    return cleaned;
  }
  
  static dynamic _cleanValue(dynamic value) {
    if (value == null) {
      return null;
    }
    
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    
    if (value is List) {
      final List cleanedList = [];
      for (final item in value) {
        final cleanedItem = _cleanValue(item);
        if (_isValidValue(cleanedItem)) {
          cleanedList.add(cleanedItem);
        }
      }
      return cleanedList.isEmpty ? null : cleanedList;
    }
    
    if (value is Map) {
      final Map<String, dynamic> cleanedMap = {};
      value.forEach((k, v) {
        final cleanedValue = _cleanValue(v);
        if (_isValidValue(cleanedValue)) {
          cleanedMap[k.toString()] = cleanedValue;
        }
      });
      return cleanedMap.isEmpty ? null : cleanedMap;
    }
    
    // For numbers, booleans, Timestamps, etc.
    return value;
  }
  
  static bool _isValidValue(dynamic value) {
    if (value == null) return false;
    
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    
    return true; // Numbers, booleans, etc. are always valid
  }
}
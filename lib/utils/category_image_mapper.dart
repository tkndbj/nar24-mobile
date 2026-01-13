// lib/utils/category_image_mapper.dart
class CategoryImageMapper {
  // Static mapping from category keys to image assets
  static const Map<String, String> _categoryImageMap = {
    // Main categories
    'Clothing & Fashion': 'assets/images/category-boxes/fashion.jpg',
    'Footwear': 'assets/images/category-boxes/shoes.jpg',
    'Accessories': 'assets/images/category-boxes/accessories.jpg',
    'Mother & Child': 'assets/images/category-boxes/child.jpg',
    'Home & Furniture': 'assets/images/category-boxes/furniture.jpg',
    'Beauty & Personal Care': 'assets/images/category-boxes/selfcare.jpg',
    'Bags & Luggage': 'assets/images/category-boxes/bags.jpg',
    'Electronics': 'assets/images/category-boxes/electronics.jpg',
    'Flowers & Gifts': 'assets/images/category-boxes/flowerandgift.jpg',
    'Sports & Outdoor': 'assets/images/category-boxes/sport.jpg',
    'Books, Stationery & Hobby': 'assets/images/category-boxes/stationary.jpeg',
    'Tools & Hardware': 'assets/images/category-boxes/toolsandhardware.jpg',
    'Pet Supplies': 'assets/images/category-boxes/pets.jpg',
    'Automotive': 'assets/images/category-boxes/automotive.jpg',
    'Health & Wellness': 'assets/images/category-boxes/healthandwellness.jpg',
  };

  // Fallback mapping for subcategories to their parent category images
  static const Map<String, String> _subcategoryFallbacks = {
    // Clothing & Fashion subcategories
    'Dresses': 'Clothing & Fashion',
    'Tops & Shirts': 'Clothing & Fashion',
    'Bottoms': 'Clothing & Fashion',
    'Outerwear': 'Clothing & Fashion',
    'Underwear & Sleepwear': 'Clothing & Fashion',
    'Swimwear': 'Clothing & Fashion',
    'Activewear': 'Clothing & Fashion',
    'Suits & Formal': 'Clothing & Fashion',
    'Traditional & Cultural': 'Clothing & Fashion',
    
    // Footwear subcategories
    'Sneakers & Athletic': 'Footwear',
    'Casual Shoes': 'Footwear',
    'Formal Shoes': 'Footwear',
    'Boots': 'Footwear',
    'Sandals & Flip-Flops': 'Footwear',
    'Slippers': 'Footwear',
    'Specialized Footwear': 'Footwear',
    
    // Accessories subcategories
    'Jewelry': 'Accessories',
    'Watches': 'Accessories',
    'Belts': 'Accessories',
    'Hats & Caps': 'Accessories',
    'Scarves & Wraps': 'Accessories',
    'Sunglasses & Eyewear': 'Accessories',
    'Gloves': 'Accessories',
    'Hair Accessories': 'Accessories',
    'Other Accessories': 'Accessories',
    
    // Mother & Child subcategories
    'Baby Clothing': 'Mother & Child',
    'Kids Clothing': 'Mother & Child',
    'Kids Footwear': 'Mother & Child',
    'Toys & Games': 'Mother & Child',
    'Baby Care': 'Mother & Child',
    'Maternity': 'Mother & Child',
    'Strollers & Car Seats': 'Mother & Child',
    'Feeding & Nursing': 'Mother & Child',
    'Safety & Security': 'Mother & Child',
    'Educational': 'Mother & Child',
  };

  /// Get image path for a category suggestion
  static String getImagePath(String categoryKey, {String? subcategoryKey}) {
    // Try direct category mapping first
    if (_categoryImageMap.containsKey(categoryKey)) {
      return _categoryImageMap[categoryKey]!;
    }
    
    // Try subcategory fallback
    if (subcategoryKey != null && _subcategoryFallbacks.containsKey(subcategoryKey)) {
      final parentCategory = _subcategoryFallbacks[subcategoryKey]!;
      return _categoryImageMap[parentCategory] ?? _getDefaultImage();
    }
    
    // Fallback to keyword matching
    return _getImageByKeywordMatching(categoryKey) ?? _getDefaultImage();
  }

  /// Advanced keyword matching for edge cases
  static String? _getImageByKeywordMatching(String categoryKey) {
    final lowerKey = categoryKey.toLowerCase();
    
    // Fashion-related keywords
    if (lowerKey.contains('cloth') || lowerKey.contains('fashion') || 
        lowerKey.contains('apparel') || lowerKey.contains('wear')) {
      return _categoryImageMap['Clothing & Fashion'];
    }
    
    // Footwear-related keywords
    if (lowerKey.contains('shoe') || lowerKey.contains('boot') || 
        lowerKey.contains('sandal') || lowerKey.contains('footwear')) {
      return _categoryImageMap['Footwear'];
    }
    
    // Electronics-related keywords
    if (lowerKey.contains('electronic') || lowerKey.contains('gadget') || 
        lowerKey.contains('tech') || lowerKey.contains('device')) {
      return _categoryImageMap['Electronics'];
    }
    
    // Home-related keywords
    if (lowerKey.contains('home') || lowerKey.contains('furniture') || 
        lowerKey.contains('decor') || lowerKey.contains('kitchen')) {
      return _categoryImageMap['Home & Furniture'];
    }
    
    // Beauty-related keywords
    if (lowerKey.contains('beauty') || lowerKey.contains('cosmetic') || 
        lowerKey.contains('care') || lowerKey.contains('skincare')) {
      return _categoryImageMap['Beauty & Personal Care'];
    }
    
    // Sports-related keywords
    if (lowerKey.contains('sport') || lowerKey.contains('fitness') || 
        lowerKey.contains('outdoor') || lowerKey.contains('exercise')) {
      return _categoryImageMap['Sports & Outdoor'];
    }
    
    // Bags-related keywords
    if (lowerKey.contains('bag') || lowerKey.contains('luggage') || 
        lowerKey.contains('backpack') || lowerKey.contains('purse')) {
      return _categoryImageMap['Bags & Luggage'];
    }
    
    return null;
  }

  /// Default fallback image
  static String _getDefaultImage() {
    return 'assets/images/category-boxes/fashion.jpg'; // Most generic fallback
  }

  /// Get all available category images for validation
  static List<String> getAllImagePaths() {
    return _categoryImageMap.values.toList();
  }

  /// Validate if image exists for category
  static bool hasImageForCategory(String categoryKey) {
    return _categoryImageMap.containsKey(categoryKey) || 
           _getImageByKeywordMatching(categoryKey) != null;
  }
}
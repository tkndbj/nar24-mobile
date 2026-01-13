// File: lib/utils/attribute_route_mapper.dart

/// Maps product attributes to their corresponding detail screen routes.
/// This enables direct navigation to specific attribute editing screens
/// without going through the entire product flow.
class AttributeRouteMapper {
  /// Maps an attribute key to its corresponding screen route.
  /// Returns null if no specific screen exists for the attribute.
  static String? getRouteForAttribute(String attributeKey) {
    // Map of attribute keys to their routes
    final Map<String, String> attributeRoutes = {
      // Gender
      'gender': '/list_gender',

      // Clothing attributes (all handled by clothing screen)
      'clothingSizes': '/list_clothing',
      'clothingFit': '/list_clothing',
      'clothingType': '/list_clothing',
      'clothingTypes': '/list_clothing',

      // Pant attributes
      'pantSizes': '/list_pant',
      'pantFabricType': '/list_pant', // ✅ ADD: Legacy key
      'pantFabricTypes': '/list_pant',

      // Footwear attributes
      'footwearSizes': '/list_footwear',

      // Jewelry attributes
      'jewelryType': '/list_jewelry_type',
      'jewelryMaterials': '/list_jewelry_mat',

      // Computer component attributes
      'computerComponent': '/list_computer_components',

      // Console attributes
      'consoleBrand': '/list_consoles',
      'consoleVariant': '/list_consoles',

      // Kitchen appliance attributes
      'kitchenAppliance': '/list_kitchen_appliances',

      // White goods attributes
      'whiteGood': '/list_white_goods',
    };

    return attributeRoutes[attributeKey];
  }

  /// Gets all attributes that are edited by a specific screen route.
  /// This helps identify which attributes will be affected when navigating to a screen.
  static List<String> getAttributesForRoute(String route) {
    final Map<String, List<String>> routeAttributes = {
      '/list_gender': ['gender'],
      '/list_clothing': ['clothingSizes', 'clothingFit', 'clothingType', 'clothingTypes'],
      '/list_pant': ['pantSizes', 'pantFabricType', 'pantFabricTypes'],
      '/list_footwear': ['footwearSizes'],
      '/list_jewelry_type': ['jewelryType'],
      '/list_jewelry_mat': ['jewelryMaterials'],
      '/list_computer_components': ['computerComponent'],
      '/list_consoles': ['consoleBrand', 'consoleVariant'],
      '/list_kitchen_appliances': ['kitchenAppliance'],
      '/list_white_goods': ['whiteGood'],
    };

    return routeAttributes[route] ?? [];
  }

  /// Checks if an attribute has a dedicated editing screen.
  static bool hasEditScreen(String attributeKey) {
    return getRouteForAttribute(attributeKey) != null;
  }

  /// Special handling: Maps brand to brand screen (not an attribute but similar flow)
  static const String brandRoute = '/list_brand';

  /// Special handling: Maps colors to color options screen
  static const String colorRoute = '/list_color';
}

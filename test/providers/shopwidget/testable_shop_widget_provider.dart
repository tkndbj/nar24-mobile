// test/providers/testable_shop_widget_provider.dart
//
// TESTABLE MIRROR of ShopWidgetProvider pure logic from lib/providers/shop_widget_provider.dart
//
// This file contains EXACT copies of pure logic functions from ShopWidgetProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/shop_widget_provider.dart
//
// Last synced with: shop_widget_provider.dart (current version)

/// Shop member roles
enum ShopRole {
  owner,
  coOwner,
  editor,
  viewer,
}

/// Mirrors configuration from ShopWidgetProvider
class TestableShopWidgetConfig {
  static const int maxShopBufferSize = 500;
  static const int defaultFeaturedShopLimit = 10;
}

/// Mirrors _verifyUserStillMemberOfShop from ShopWidgetProvider
class TestableShopMembershipVerifier {
  /// Mirrors _verifyUserStillMemberOfShop from ShopWidgetProvider
  /// Verify user is still member of shop based on role
  static bool verifyUserStillMemberOfShop({
    required String uid,
    required String role,
    required Map<String, dynamic> shopData,
  }) {
    switch (role) {
      case 'owner':
        return shopData['ownerId'] == uid;
      case 'co-owner':
        final coOwners = _castToStringList(shopData['coOwners']);
        return coOwners.contains(uid);
      case 'editor':
        final editors = _castToStringList(shopData['editors']);
        return editors.contains(uid);
      case 'viewer':
        final viewers = _castToStringList(shopData['viewers']);
        return viewers.contains(uid);
      default:
        return false;
    }
  }

  /// Helper to safely cast list
  static List<String> _castToStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.cast<String>();
    }
    return [];
  }

  /// Get role from string
  static ShopRole? parseRole(String role) {
    switch (role) {
      case 'owner':
        return ShopRole.owner;
      case 'co-owner':
        return ShopRole.coOwner;
      case 'editor':
        return ShopRole.editor;
      case 'viewer':
        return ShopRole.viewer;
      default:
        return null;
    }
  }

  /// Check if role string is valid
  static bool isValidRole(String role) {
    return ['owner', 'co-owner', 'editor', 'viewer'].contains(role);
  }

  /// Get all roles a user has in a shop
  static List<String> getUserRoles({
    required String uid,
    required Map<String, dynamic> shopData,
  }) {
    final roles = <String>[];

    if (shopData['ownerId'] == uid) {
      roles.add('owner');
    }

    final coOwners = _castToStringList(shopData['coOwners']);
    if (coOwners.contains(uid)) {
      roles.add('co-owner');
    }

    final editors = _castToStringList(shopData['editors']);
    if (editors.contains(uid)) {
      roles.add('editor');
    }

    final viewers = _castToStringList(shopData['viewers']);
    if (viewers.contains(uid)) {
      roles.add('viewer');
    }

    return roles;
  }

  /// Check if user has any role in shop
  static bool hasAnyRole({
    required String uid,
    required Map<String, dynamic> shopData,
  }) {
    return getUserRoles(uid: uid, shopData: shopData).isNotEmpty;
  }
}

/// Mirrors favorite toggle logic from ShopWidgetProvider
class TestableFavoriteManager {
  final Set<String> _favoriteShopIds;

  TestableFavoriteManager([Set<String>? initialFavorites])
      : _favoriteShopIds = initialFavorites ?? {};

  Set<String> get favoriteShopIds => Set.unmodifiable(_favoriteShopIds);
  int get count => _favoriteShopIds.length;

  /// Check if shop is favorited
  bool isFavorite(String shopId) {
    return _favoriteShopIds.contains(shopId);
  }

  /// Determine action for toggle
  /// Returns true if should ADD to favorites, false if should REMOVE
  bool shouldAddOnToggle(String shopId) {
    return !_favoriteShopIds.contains(shopId);
  }

  /// Simulate adding favorite (for testing state changes)
  void addFavorite(String shopId) {
    _favoriteShopIds.add(shopId);
  }

  /// Simulate removing favorite
  void removeFavorite(String shopId) {
    _favoriteShopIds.remove(shopId);
  }

  /// Toggle favorite (local state only)
  void toggle(String shopId) {
    if (_favoriteShopIds.contains(shopId)) {
      _favoriteShopIds.remove(shopId);
    } else {
      _favoriteShopIds.add(shopId);
    }
  }

  /// Clear all favorites
  void clear() {
    _favoriteShopIds.clear();
  }
}

/// Mirrors membership map processing from ShopWidgetProvider
class TestableMembershipProcessor {
  /// Extract shop IDs from memberOfShops map
  static List<String> extractShopIds(Map<String, dynamic>? memberOfShops) {
    if (memberOfShops == null || memberOfShops.isEmpty) {
      return [];
    }
    return memberOfShops.keys.toList();
  }

  /// Get role for a specific shop
  static String? getRoleForShop(
    Map<String, dynamic>? memberOfShops,
    String shopId,
  ) {
    if (memberOfShops == null) return null;
    final role = memberOfShops[shopId];
    return role is String ? role : null;
  }

  /// Check if user has any memberships
  static bool hasAnyMembership(Map<String, dynamic>? memberOfShops) {
    return memberOfShops != null && memberOfShops.isNotEmpty;
  }

  /// Get count of memberships
  static int getMembershipCount(Map<String, dynamic>? memberOfShops) {
    return memberOfShops?.length ?? 0;
  }

  /// Build cleanup map for invalid memberships
  /// Returns map of shopId -> FieldValue.delete() for Firestore update
  static Map<String, String> buildCleanupKeys(List<String> shopIdsToRemove) {
    final updates = <String, String>{};
    for (final shopId in shopIdsToRemove) {
      updates['memberOfShops.$shopId'] = 'DELETE';
    }
    return updates;
  }
}

/// Mirrors follower count logic
class TestableFollowerCountCalculator {
  /// Calculate follower count change for toggle
  /// Returns +1 for follow, -1 for unfollow
  static int getFollowerCountDelta({
    required bool isCurrentlyFavorite,
  }) {
    return isCurrentlyFavorite ? -1 : 1;
  }
}

/// Mirrors shop list management
class TestableShopListManager<T> {
  final List<T> _shops = [];
  final int maxSize;

  TestableShopListManager({this.maxSize = TestableShopWidgetConfig.maxShopBufferSize});

  List<T> get shops => List.unmodifiable(_shops);
  int get length => _shops.length;
  bool get isEmpty => _shops.isEmpty;
  bool get isNotEmpty => _shops.isNotEmpty;

  /// Add shops (replaces existing)
  void setShops(List<T> newShops) {
    _shops.clear();
    // Enforce max size
    if (newShops.length > maxSize) {
      _shops.addAll(newShops.take(maxSize));
    } else {
      _shops.addAll(newShops);
    }
  }

  /// Clear all shops
  void clear() {
    _shops.clear();
  }

  /// Check if at capacity
  bool get isAtCapacity => _shops.length >= maxSize;
}
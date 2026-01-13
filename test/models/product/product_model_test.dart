// test/model/product/product_model_test.dart
//
// Unit tests for Product model parsing logic
// Tests the EXACT parsing functions from lib/models/product.dart
//
// Run: flutter test test/model/product/product_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_product_model.dart';

void main() {
  group('TestableProductParser', () {
    // ========================================================================
    // safeDouble Tests
    // ========================================================================
    group('safeDouble', () {
      test('returns double as-is', () {
        expect(TestableProductParser.safeDouble(99.99), 99.99);
        expect(TestableProductParser.safeDouble(0.0), 0.0);
        expect(TestableProductParser.safeDouble(-50.5), -50.5);
      });

      test('converts int to double', () {
        expect(TestableProductParser.safeDouble(100), 100.0);
        expect(TestableProductParser.safeDouble(0), 0.0);
        expect(TestableProductParser.safeDouble(-25), -25.0);
      });

      test('parses String to double', () {
        expect(TestableProductParser.safeDouble('99.99'), 99.99);
        expect(TestableProductParser.safeDouble('100'), 100.0);
        expect(TestableProductParser.safeDouble('-50.5'), -50.5);
        expect(TestableProductParser.safeDouble('0'), 0.0);
      });

      test('returns default for null', () {
        expect(TestableProductParser.safeDouble(null), 0.0);
        expect(TestableProductParser.safeDouble(null, 50.0), 50.0);
      });

      test('returns default for unparseable String', () {
        expect(TestableProductParser.safeDouble('abc'), 0.0);
        expect(TestableProductParser.safeDouble(''), 0.0);
        expect(TestableProductParser.safeDouble('12.34.56'), 0.0);
        expect(TestableProductParser.safeDouble('\$99.99'), 0.0);
      });

      test('returns default for unsupported types', () {
        expect(TestableProductParser.safeDouble([1, 2, 3]), 0.0);
        expect(TestableProductParser.safeDouble({'price': 99}), 0.0);
        expect(TestableProductParser.safeDouble(true), 0.0);
      });

      test('handles Firestore-like String prices', () {
        // Common Firestore edge case: prices stored as strings
        expect(TestableProductParser.safeDouble('1299.00'), 1299.0);
        expect(TestableProductParser.safeDouble('0.99'), 0.99);
        expect(TestableProductParser.safeDouble('10000'), 10000.0);
      });
    });

    // ========================================================================
    // safeInt Tests
    // ========================================================================
    group('safeInt', () {
      test('returns int as-is', () {
        expect(TestableProductParser.safeInt(100), 100);
        expect(TestableProductParser.safeInt(0), 0);
        expect(TestableProductParser.safeInt(-25), -25);
      });

      test('converts double to int (truncates)', () {
        expect(TestableProductParser.safeInt(99.9), 99);
        expect(TestableProductParser.safeInt(99.1), 99);
        expect(TestableProductParser.safeInt(0.5), 0);
        expect(TestableProductParser.safeInt(-5.7), -5);
      });

      test('parses String to int', () {
        expect(TestableProductParser.safeInt('100'), 100);
        expect(TestableProductParser.safeInt('0'), 0);
        expect(TestableProductParser.safeInt('-25'), -25);
      });

      test('returns default for null', () {
        expect(TestableProductParser.safeInt(null), 0);
        expect(TestableProductParser.safeInt(null, 10), 10);
      });

      test('returns default for unparseable String', () {
        expect(TestableProductParser.safeInt('abc'), 0);
        expect(TestableProductParser.safeInt(''), 0);
        expect(TestableProductParser.safeInt('12.34'), 0); // Note: int.tryParse fails on decimals
      });

      test('handles quantity-like values', () {
        expect(TestableProductParser.safeInt('50'), 50);
        expect(TestableProductParser.safeInt(50.0), 50);
      });
    });

    // ========================================================================
    // safeString Tests
    // ========================================================================
    group('safeString', () {
      test('returns String as-is', () {
        expect(TestableProductParser.safeString('hello'), 'hello');
        expect(TestableProductParser.safeString(''), '');
        expect(TestableProductParser.safeString('  spaced  '), '  spaced  ');
      });

      test('converts other types to String', () {
        expect(TestableProductParser.safeString(123), '123');
        expect(TestableProductParser.safeString(99.99), '99.99');
        expect(TestableProductParser.safeString(true), 'true');
        expect(TestableProductParser.safeString(false), 'false');
      });

      test('returns default for null', () {
        expect(TestableProductParser.safeString(null), '');
        expect(TestableProductParser.safeString(null, 'default'), 'default');
      });
    });

    // ========================================================================
    // safeStringNullable Tests
    // ========================================================================
    group('safeStringNullable', () {
      test('returns String as-is when non-empty', () {
        expect(TestableProductParser.safeStringNullable('hello'), 'hello');
        expect(TestableProductParser.safeStringNullable('Male'), 'Male');
      });

      test('returns null for null input', () {
        expect(TestableProductParser.safeStringNullable(null), null);
      });

      test('returns null for empty or whitespace String', () {
        expect(TestableProductParser.safeStringNullable(''), null);
        expect(TestableProductParser.safeStringNullable('   '), null);
        expect(TestableProductParser.safeStringNullable('\t\n'), null);
      });

      test('converts and trims other types', () {
        expect(TestableProductParser.safeStringNullable(123), '123');
        expect(TestableProductParser.safeStringNullable(true), 'true');
      });
    });

    // ========================================================================
    // safeStringList Tests
    // ========================================================================
    group('safeStringList', () {
      test('returns empty list for null', () {
        expect(TestableProductParser.safeStringList(null), []);
      });

      test('converts List elements to strings', () {
        expect(
          TestableProductParser.safeStringList(['a', 'b', 'c']),
          ['a', 'b', 'c'],
        );
        expect(
          TestableProductParser.safeStringList([1, 2, 3]),
          ['1', '2', '3'],
        );
        expect(
          TestableProductParser.safeStringList([true, false]),
          ['true', 'false'],
        );
      });

      test('handles mixed type List', () {
        expect(
          TestableProductParser.safeStringList(['url1', 123, true]),
          ['url1', '123', 'true'],
        );
      });

      test('wraps single String in list', () {
        expect(
          TestableProductParser.safeStringList('single_url'),
          ['single_url'],
        );
      });

      test('returns empty list for empty String', () {
        expect(TestableProductParser.safeStringList(''), []);
      });

      test('handles imageUrls from Firestore', () {
        final firestoreUrls = [
          'https://firebase.com/img1.jpg',
          'https://firebase.com/img2.jpg',
        ];
        expect(
          TestableProductParser.safeStringList(firestoreUrls),
          firestoreUrls,
        );
      });
    });

    // ========================================================================
    // safeColorQuantities Tests
    // ========================================================================
    group('safeColorQuantities', () {
      test('returns empty map for non-Map input', () {
        expect(TestableProductParser.safeColorQuantities(null), {});
        expect(TestableProductParser.safeColorQuantities('string'), {});
        expect(TestableProductParser.safeColorQuantities([1, 2, 3]), {});
      });

      test('parses Map with int values', () {
        expect(
          TestableProductParser.safeColorQuantities({'Red': 10, 'Blue': 5}),
          {'Red': 10, 'Blue': 5},
        );
      });

      test('converts String keys and values', () {
        expect(
          TestableProductParser.safeColorQuantities({'Red': '10', 'Blue': '5'}),
          {'Red': 10, 'Blue': 5},
        );
      });

      test('converts double values to int', () {
        expect(
          TestableProductParser.safeColorQuantities({'Red': 10.0, 'Blue': 5.9}),
          {'Red': 10, 'Blue': 5},
        );
      });

      test('handles Firestore Map<dynamic, dynamic>', () {
        final Map<dynamic, dynamic> firestoreMap = {
          'Red': 10,
          'Blue': '5',
          'Green': 3.0,
        };
        expect(
          TestableProductParser.safeColorQuantities(firestoreMap),
          {'Red': 10, 'Blue': 5, 'Green': 3},
        );
      });

      test('handles non-string keys', () {
        expect(
          TestableProductParser.safeColorQuantities({1: 10, 2: 5}),
          {'1': 10, '2': 5},
        );
      });
    });

    // ========================================================================
    // safeColorImages Tests
    // ========================================================================
    group('safeColorImages', () {
      test('returns empty map for non-Map input', () {
        expect(TestableProductParser.safeColorImages(null), {});
        expect(TestableProductParser.safeColorImages('string'), {});
        expect(TestableProductParser.safeColorImages([1, 2, 3]), {});
      });

      test('parses Map with List<String> values', () {
        final input = {
          'Red': ['img1.jpg', 'img2.jpg'],
          'Blue': ['img3.jpg'],
        };
        expect(TestableProductParser.safeColorImages(input), input);
      });

      test('converts List elements to strings', () {
        final input = {
          'Red': [1, 2, 3],
        };
        expect(
          TestableProductParser.safeColorImages(input),
          {
            'Red': ['1', '2', '3']
          },
        );
      });

      test('wraps single String value in list', () {
        final input = {
          'Red': 'single_img.jpg',
          'Blue': '',
        };
        expect(
          TestableProductParser.safeColorImages(input),
          {
            'Red': ['single_img.jpg'],
            // 'Blue' is empty string so not included
          },
        );
      });

      test('skips non-List, non-String values', () {
        final input = {
          'Red': ['img.jpg'],
          'Blue': 123, // Not a list or non-empty string
          'Green': null,
        };
        expect(
          TestableProductParser.safeColorImages(input),
          {
            'Red': ['img.jpg']
          },
        );
      });

      test('handles Firestore Map<dynamic, dynamic>', () {
        final Map<dynamic, dynamic> firestoreMap = {
          'Red': ['img1.jpg', 'img2.jpg'],
          'Blue': 'single.jpg',
        };
        expect(
          TestableProductParser.safeColorImages(firestoreMap),
          {
            'Red': ['img1.jpg', 'img2.jpg'],
            'Blue': ['single.jpg'],
          },
        );
      });
    });

    // ========================================================================
    // safeBundleData Tests
    // ========================================================================
    group('safeBundleData', () {
      test('returns null for null input', () {
        expect(TestableProductParser.safeBundleData(null), null);
      });

      test('returns null for non-List input', () {
        expect(TestableProductParser.safeBundleData('string'), null);
        expect(TestableProductParser.safeBundleData(123), null);
        expect(TestableProductParser.safeBundleData({'key': 'value'}), null);
      });

      test('parses List of Map<String, dynamic>', () {
        final input = [
          {'productId': 'p1', 'quantity': 2},
          {'productId': 'p2', 'quantity': 1},
        ];
        expect(TestableProductParser.safeBundleData(input), input);
      });

      test('converts Map<dynamic, dynamic> to Map<String, dynamic>', () {
        final List<dynamic> input = [
          <dynamic, dynamic>{'productId': 'p1', 'quantity': 2},
        ];
        final result = TestableProductParser.safeBundleData(input);
        expect(result, isNotNull);
        expect(result![0], isA<Map<String, dynamic>>());
        expect(result[0]['productId'], 'p1');
      });

      test('handles empty list', () {
        expect(TestableProductParser.safeBundleData([]), []);
      });

      test('converts non-Map items to empty map', () {
        final input = [
          {'productId': 'p1'},
          'invalid',
          123,
        ];
        final result = TestableProductParser.safeBundleData(input);
        expect(result, isNotNull);
        expect(result!.length, 3);
        expect(result[0], {'productId': 'p1'});
        expect(result[1], {});
        expect(result[2], {});
      });
    });

    // ========================================================================
    // parseCreatedAt Tests
    // ========================================================================
    group('parseCreatedAt', () {
      test('parses milliseconds int', () {
        final timestamp = DateTime(2024, 1, 15, 10, 30).millisecondsSinceEpoch;
        final result = TestableProductParser.parseCreatedAt(timestamp);
        expect(result.year, 2024);
        expect(result.month, 1);
        expect(result.day, 15);
      });

      test('parses ISO String', () {
        final result = TestableProductParser.parseCreatedAt('2024-06-15T14:30:00Z');
        expect(result.year, 2024);
        expect(result.month, 6);
        expect(result.day, 15);
      });

      test('returns now for invalid String', () {
        final before = DateTime.now();
        final result = TestableProductParser.parseCreatedAt('invalid-date');
        final after = DateTime.now();

        expect(result.isAfter(before.subtract(Duration(seconds: 1))), true);
        expect(result.isBefore(after.add(Duration(seconds: 1))), true);
      });

      test('returns now for null', () {
        final before = DateTime.now();
        final result = TestableProductParser.parseCreatedAt(null);
        final after = DateTime.now();

        expect(result.isAfter(before.subtract(Duration(seconds: 1))), true);
        expect(result.isBefore(after.add(Duration(seconds: 1))), true);
      });

      test('returns now for unsupported type', () {
        final before = DateTime.now();
        final result = TestableProductParser.parseCreatedAt({'invalid': true});
        final after = DateTime.now();

        expect(result.isAfter(before.subtract(Duration(seconds: 1))), true);
        expect(result.isBefore(after.add(Duration(seconds: 1))), true);
      });
    });

    // ========================================================================
    // parseTimestamp Tests (nullable version)
    // ========================================================================
    group('parseTimestamp', () {
      test('returns null for null input', () {
        expect(TestableProductParser.parseTimestamp(null), null);
      });

      test('parses milliseconds int', () {
        final timestamp = DateTime(2024, 3, 20, 8, 0).millisecondsSinceEpoch;
        final result = TestableProductParser.parseTimestamp(timestamp);
        expect(result, isNotNull);
        expect(result!.year, 2024);
        expect(result.month, 3);
        expect(result.day, 20);
      });

      test('parses ISO String', () {
        final result = TestableProductParser.parseTimestamp('2024-12-25T00:00:00Z');
        expect(result, isNotNull);
        expect(result!.month, 12);
        expect(result.day, 25);
      });

      test('returns null for invalid String', () {
        expect(TestableProductParser.parseTimestamp('not-a-date'), null);
      });

      test('returns null for unsupported type', () {
        expect(TestableProductParser.parseTimestamp(['array']), null);
        expect(TestableProductParser.parseTimestamp({'map': true}), null);
      });
    });

    // ========================================================================
    // normalizeAlgoliaId Tests
    // ========================================================================
    group('normalizeAlgoliaId', () {
      test('returns empty string for null', () {
        expect(TestableProductParser.normalizeAlgoliaId(null), '');
      });

      test('returns empty string for empty input', () {
        expect(TestableProductParser.normalizeAlgoliaId(''), '');
      });

      test('removes products_ prefix', () {
        expect(
          TestableProductParser.normalizeAlgoliaId('products_abc123'),
          'abc123',
        );
      });

      test('removes shop_products_ prefix', () {
        expect(
          TestableProductParser.normalizeAlgoliaId('shop_products_xyz789'),
          'xyz789',
        );
      });

      test('returns id as-is if no prefix', () {
        expect(
          TestableProductParser.normalizeAlgoliaId('abc123'),
          'abc123',
        );
      });

      test('handles prefix at wrong position', () {
        // Prefix in middle shouldn't be removed
        expect(
          TestableProductParser.normalizeAlgoliaId('my_products_123'),
          'my_products_123',
        );
      });
    });

    // ========================================================================
    // detectSourceCollection Tests
    // ========================================================================
    group('detectSourceCollection', () {
      test('detects products collection', () {
        expect(
          TestableProductParser.detectSourceCollection('products/abc123'),
          'products',
        );
      });

      test('detects shop_products collection', () {
        expect(
          TestableProductParser.detectSourceCollection('shop_products/xyz789'),
          'shop_products',
        );
      });

      test('returns null for unknown collection', () {
        expect(
          TestableProductParser.detectSourceCollection('other/doc123'),
          null,
        );
      });

      test('returns null for empty path', () {
        expect(TestableProductParser.detectSourceCollection(''), null);
      });
    });
  });

  // ==========================================================================
  // TestableProductData.fromJson Tests
  // ==========================================================================
  group('TestableProductData.fromJson', () {
    test('parses complete valid JSON', () {
      final json = {
        'id': 'prod_123',
        'productName': 'Test Product',
        'description': 'A great product',
        'price': 99.99,
        'currency': 'USD',
        'condition': 'New',
        'brandModel': 'BrandX Model1',
        'imageUrls': ['img1.jpg', 'img2.jpg'],
        'averageRating': 4.5,
        'reviewCount': 100,
        'gender': 'Unisex',
        'originalPrice': 129.99,
        'discountPercentage': 20,
        'colorQuantities': {'Red': 10, 'Blue': 5},
        'colorImages': {
          'Red': ['red1.jpg'],
          'Blue': ['blue1.jpg']
        },
        'availableColors': ['Red', 'Blue'],
        'userId': 'user_456',
        'ownerId': 'owner_789',
        'shopId': 'shop_001',
        'sellerName': 'Test Seller',
        'category': 'Electronics',
        'subcategory': 'Phones',
        'subsubcategory': 'Smartphones',
        'quantity': 50,
        'deliveryOption': 'Express',
        'createdAt': 1704067200000, // Jan 1, 2024
        'isFeatured': true,
        'isTrending': false,
        'isBoosted': true,
        'paused': false,
        'attributes': {'color': 'red', 'size': 'M'},
      };

      final product = TestableProductData.fromJson(json);

      expect(product.id, 'prod_123');
      expect(product.productName, 'Test Product');
      expect(product.price, 99.99);
      expect(product.currency, 'USD');
      expect(product.imageUrls, ['img1.jpg', 'img2.jpg']);
      expect(product.averageRating, 4.5);
      expect(product.reviewCount, 100);
      expect(product.originalPrice, 129.99);
      expect(product.discountPercentage, 20);
      expect(product.colorQuantities, {'Red': 10, 'Blue': 5});
      expect(product.isFeatured, true);
      expect(product.isBoosted, true);
      expect(product.attributes, {'color': 'red', 'size': 'M'});
    });

    test('handles minimal JSON with defaults', () {
      final json = <String, dynamic>{};

      final product = TestableProductData.fromJson(json);

      expect(product.id, '');
      expect(product.productName, '');
      expect(product.price, 0.0);
      expect(product.currency, 'TL');
      expect(product.condition, 'Brand New');
      expect(product.imageUrls, []);
      expect(product.averageRating, 0.0);
      expect(product.reviewCount, 0);
      expect(product.colorQuantities, {});
      expect(product.colorImages, {});
      expect(product.isFeatured, false);
      expect(product.paused, false);
      expect(product.deliveryOption, 'Self Delivery');
    });

    test('handles null values gracefully', () {
      final json = {
        'id': null,
        'productName': null,
        'price': null,
        'imageUrls': null,
        'colorQuantities': null,
        'attributes': null,
      };

      final product = TestableProductData.fromJson(json);

      expect(product.id, '');
      expect(product.productName, '');
      expect(product.price, 0.0);
      expect(product.imageUrls, []);
      expect(product.colorQuantities, {});
      expect(product.attributes, {});
    });

    test('parses bundleData correctly', () {
      final json = {
        'id': 'bundle_1',
        'bundleData': [
          {'productId': 'p1', 'quantity': 2, 'price': 50.0},
          {'productId': 'p2', 'quantity': 1, 'price': 30.0},
        ],
        'bundleIds': ['p1', 'p2'],
      };

      final product = TestableProductData.fromJson(json);

      expect(product.bundleData, isNotNull);
      expect(product.bundleData!.length, 2);
      expect(product.bundleData![0]['productId'], 'p1');
      expect(product.bundleIds, ['p1', 'p2']);
    });

    test('parses boost timestamps', () {
      final json = {
        'id': 'prod_1',
        'boostStartTime': 1704067200000, // Jan 1, 2024
        'boostEndTime': '2024-01-08T00:00:00Z',
      };

      final product = TestableProductData.fromJson(json);

      expect(product.boostStartTime, isNotNull);
      expect(product.boostStartTime!.year, 2024);
      expect(product.boostEndTime, isNotNull);
      expect(product.boostEndTime!.month, 1);
    });
  });

  // ==========================================================================
  // TestableProductData.fromAlgolia Tests
  // ==========================================================================
  group('TestableProductData.fromAlgolia', () {
    test('normalizes objectID with products_ prefix', () {
      final json = {
        'objectID': 'products_abc123',
        'productName': 'Algolia Product',
        'price': 50.0,
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.id, 'abc123');
    });

    test('normalizes objectID with shop_products_ prefix', () {
      final json = {
        'objectID': 'shop_products_xyz789',
        'productName': 'Shop Product',
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.id, 'xyz789');
    });

    test('keeps objectID as-is without prefix', () {
      final json = {
        'objectID': 'simple_id',
        'productName': 'Simple Product',
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.id, 'simple_id');
    });

    test('handles missing objectID', () {
      final json = {
        'productName': 'No ID Product',
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.id, '');
    });

    test('parses numeric fields as num then converts', () {
      final json = {
        'objectID': 'prod_1',
        'price': 99, // int instead of double
        'averageRating': 4, // int instead of double
        'reviewCount': 50.0, // double instead of int
        'quantity': 10.5, // double instead of int
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.price, 99.0);
      expect(product.averageRating, 4.0);
      expect(product.reviewCount, 50);
      expect(product.quantity, 10);
    });

    test('uses toString for string fields', () {
      final json = {
        'objectID': 123, // number instead of string
        'productName': 456,
        'currency': 789,
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.id, '123');
      expect(product.productName, '456');
      expect(product.currency, '789');
    });

    test('parses complete Algolia response', () {
      final json = {
        'objectID': 'products_search_123',
        'productName': 'Search Result Product',
        'description': 'Found via Algolia',
        'price': 199.99,
        'currency': 'EUR',
        'condition': 'Used',
        'imageUrls': ['search_img.jpg'],
        'category': 'Fashion',
        'subcategory': 'Shoes',
        'availableColors': ['Black', 'White'],
        'colorQuantities': {'Black': 5, 'White': 3},
        'userId': 'seller_1',
        'isFeatured': true,
      };

      final product = TestableProductData.fromAlgolia(json);

      expect(product.id, 'search_123');
      expect(product.productName, 'Search Result Product');
      expect(product.price, 199.99);
      expect(product.currency, 'EUR');
      expect(product.category, 'Fashion');
      expect(product.availableColors, ['Black', 'White']);
      expect(product.isFeatured, true);
    });
  });

  // ==========================================================================
  // TestableProductData.fromDocument Tests
  // ==========================================================================
  group('TestableProductData.fromDocument', () {
    test('uses docId as product id', () {
      final product = TestableProductData.fromDocument(
        'doc_123',
        {'productName': 'Document Product'},
      );

      expect(product.id, 'doc_123');
    });

    test('detects source collection from path', () {
      final product1 = TestableProductData.fromDocument(
        'doc_1',
        {},
        documentPath: 'products/doc_1',
      );
      expect(product1.sourceCollection, 'products');

      final product2 = TestableProductData.fromDocument(
        'doc_2',
        {},
        documentPath: 'shop_products/doc_2',
      );
      expect(product2.sourceCollection, 'shop_products');

      final product3 = TestableProductData.fromDocument(
        'doc_3',
        {},
        documentPath: 'other/doc_3',
      );
      expect(product3.sourceCollection, null);
    });

    test('uses title as fallback for productName', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {'title': 'Product Title'},
      );

      expect(product.productName, 'Product Title');
    });

    test('prefers productName over title', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'productName': 'Product Name',
          'title': 'Product Title',
        },
      );

      expect(product.productName, 'Product Name');
    });

    test('uses brand as fallback for brandModel', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {'brand': 'BrandName'},
      );

      expect(product.brandModel, 'BrandName');
    });

    test('handles String prices from Firestore', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {'price': '99.99'},
      );

      expect(product.price, 99.99);
    });

    test('handles int prices from Firestore', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {'price': 100},
      );

      expect(product.price, 100.0);
    });

    test('handles String quantities', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'quantity': '25',
          'colorQuantities': {'Red': '10', 'Blue': '15'},
        },
      );

      expect(product.quantity, 25);
      expect(product.colorQuantities, {'Red': 10, 'Blue': 15});
    });

    test('handles Map<dynamic, dynamic> from Firestore', () {
      final Map<dynamic, dynamic> firestoreData = {
        'productName': 'Firestore Product',
        'price': 50.0,
        'colorQuantities': <dynamic, dynamic>{'Red': 5},
        'colorImages': <dynamic, dynamic>{
          'Red': ['red.jpg']
        },
      };

      // Convert to Map<String, dynamic> as fromDocument expects
      final data = Map<String, dynamic>.from(firestoreData);
      final product = TestableProductData.fromDocument('doc_1', data);

      expect(product.productName, 'Firestore Product');
      expect(product.colorQuantities, {'Red': 5});
    });

    test('handles boolean-like values', () {
      // Firestore sometimes returns truthy values
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'isFeatured': true,
          'isTrending': 1, // truthy but not bool
          'isBoosted': 'true', // string
          'paused': false,
        },
      );

      expect(product.isFeatured, true);
      // Note: The parser uses == true, so non-bool values become false
      expect(product.isTrending, false);
      expect(product.isBoosted, false);
      expect(product.paused, false);
    });

    test('provides sensible defaults', () {
      final product = TestableProductData.fromDocument('doc_1', {});

      expect(product.productName, '');
      expect(product.currency, 'TL');
      expect(product.condition, 'Brand New');
      expect(product.sellerName, 'Unknown');
      expect(product.category, 'Uncategorized');
      expect(product.deliveryOption, 'Self Delivery');
    });

    test('parses complete Firestore document', () {
      final data = {
        'productName': 'Complete Product',
        'description': 'Full description',
        'price': 299.99,
        'currency': 'TL',
        'condition': 'Like New',
        'brandModel': 'Premium Brand',
        'imageUrls': ['img1.jpg', 'img2.jpg', 'img3.jpg'],
        'averageRating': 4.8,
        'reviewCount': 250,
        'gender': 'Female',
        'originalPrice': 399.99,
        'discountPercentage': 25,
        'maxQuantity': 5,
        'discountThreshold': 3,
        'bulkDiscountPercentage': 10,
        'colorQuantities': {'Pink': 20, 'Purple': 15},
        'colorImages': {
          'Pink': ['pink1.jpg', 'pink2.jpg'],
          'Purple': ['purple1.jpg'],
        },
        'bundleData': [
          {'productId': 'acc_1', 'quantity': 1}
        ],
        'bundleIds': ['acc_1'],
        'availableColors': ['Pink', 'Purple'],
        'userId': 'seller_premium',
        'ownerId': 'owner_premium',
        'shopId': 'shop_premium',
        'sellerName': 'Premium Seller',
        'category': 'Fashion',
        'subcategory': 'Dresses',
        'subsubcategory': 'Evening',
        'quantity': 35,
        'deliveryOption': 'Free Shipping',
        'createdAt': 1704067200000,
        'boostStartTime': 1704153600000,
        'boostEndTime': 1704758400000,
        'isFeatured': true,
        'isTrending': true,
        'isBoosted': true,
        'paused': false,
        'attributes': {'material': 'silk', 'length': 'midi'},
      };

      final product = TestableProductData.fromDocument(
        'premium_001',
        data,
        documentPath: 'shop_products/premium_001',
      );

      expect(product.id, 'premium_001');
      expect(product.sourceCollection, 'shop_products');
      expect(product.productName, 'Complete Product');
      expect(product.price, 299.99);
      expect(product.originalPrice, 399.99);
      expect(product.discountPercentage, 25);
      expect(product.gender, 'Female');
      expect(product.colorQuantities, {'Pink': 20, 'Purple': 15});
      expect(product.bundleData!.length, 1);
      expect(product.isFeatured, true);
      expect(product.isTrending, true);
      expect(product.attributes['material'], 'silk');
    });
  });

  // ==========================================================================
  // Real-World Edge Cases
  // ==========================================================================
  group('Real-World Edge Cases', () {
    test('handles price as various string formats', () {
      // Common Firestore inconsistencies
      expect(TestableProductParser.safeDouble('1,299.99'), 0.0); // Comma format fails
      expect(TestableProductParser.safeDouble('1299.99'), 1299.99);
      expect(TestableProductParser.safeDouble('₺99.99'), 0.0); // Currency symbol fails
      expect(TestableProductParser.safeDouble('99.99 TL'), 0.0); // Suffix fails
    });

    test('handles empty colorQuantities gracefully', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'colorQuantities': {},
          'availableColors': ['Red'], // Mismatch: colors listed but no quantities
        },
      );

      expect(product.colorQuantities, {});
      expect(product.availableColors, ['Red']);
    });

    test('handles mismatched colorImages and availableColors', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'availableColors': ['Red', 'Blue', 'Green'],
          'colorImages': {
            'Red': ['red.jpg'],
            // Blue and Green missing
          },
        },
      );

      expect(product.availableColors.length, 3);
      expect(product.colorImages.length, 1);
      expect(product.colorImages.containsKey('Blue'), false);
    });

    test('handles very large numbers', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'price': 9999999.99,
          'quantity': 1000000,
          'reviewCount': 999999,
        },
      );

      expect(product.price, 9999999.99);
      expect(product.quantity, 1000000);
      expect(product.reviewCount, 999999);
    });

    test('handles negative values (invalid but possible)', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'price': -10.0,
          'quantity': -5,
          'averageRating': -1.0,
        },
      );

      // Parser accepts negative values - business logic should validate
      expect(product.price, -10.0);
      expect(product.quantity, -5);
      expect(product.averageRating, -1.0);
    });

    test('handles unicode in product names', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'productName': 'Ürün Adı 中文 العربية 🎉',
          'description': 'Açıklama with émojis 🛍️',
        },
      );

      expect(product.productName, 'Ürün Adı 中文 العربية 🎉');
      expect(product.description, 'Açıklama with émojis 🛍️');
    });

    test('handles extremely long strings', () {
      final longString = 'A' * 10000;
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'productName': longString,
          'description': longString,
        },
      );

      expect(product.productName.length, 10000);
      expect(product.description.length, 10000);
    });

    test('Algolia search with minimal data', () {
      // Algolia might return sparse results
      final product = TestableProductData.fromAlgolia({
        'objectID': 'products_sparse_1',
        'productName': 'Sparse Product',
        // Everything else missing
      });

      expect(product.id, 'sparse_1');
      expect(product.productName, 'Sparse Product');
      expect(product.price, 0.0);
      expect(product.colorQuantities, {});
    });

    test('JSON cache with stale data structure', () {
      // Older cached data might have different field names
      final product = TestableProductData.fromJson({
        'id': 'cached_1',
        'productName': 'Cached Product',
        'price': 50.0,
        // Old field names that might exist in cache
        'oldFieldName': 'ignored',
      });

      expect(product.id, 'cached_1');
      expect(product.price, 50.0);
    });

    test('handles attributes as non-map', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'attributes': 'not a map',
        },
      );

      expect(product.attributes, {});
    });

    test('handles createdAt as 0', () {
      final product = TestableProductData.fromDocument(
        'doc_1',
        {
          'createdAt': 0,
        },
      );

      // 0 milliseconds = Jan 1, 1970
      expect(product.createdAt.year, 1970);
    });
  });
}
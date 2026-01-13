// functions/test/impression-count/impression-utils.test.js
//
// Unit tests for impression count utility functions
// Tests the EXACT logic from impression cloud functions
//
// Run: npx jest test/impression-count/impression-utils.test.js

const {
    // Constants
    MAX_UNIQUE_PRODUCTS,
    CHUNK_SIZE,
    MAX_BATCH_SIZE,
    FIRESTORE_BATCH_LIMIT,
    COLLECTION_PREFIXES,

  
    // Validation
    validateProductIds,
    validateWorkerRequest,
  
    // Deduplication
    deduplicateAndCount,
    limitProducts,
  
    // Chunking
    chunkArray,
    calculateChunkCount,
  
    // Product ID normalization
    normalizeProductId,
    hasKnownPrefix,
    getCollectionFromId,
  
    // Grouping
    groupByCollection,
    countByCollection,
  
    // Age group
    getAgeGroup,
    getAllAgeGroups,
    isValidAgeGroup,
  
    // Gender
    normalizeGender,
  
    // Boosted products
    isBoostedProduct,
    classifyProducts,
  
    // Batch management
    shouldCommitBatch,
    calculateOperationsNeeded,
    willFitInBatch,
  
    // Field paths
    buildDemographicsPath,
    buildAgeGroupPath,
  
    // Response
    buildSuccessResponse,
  } = require('./impression-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('MAX_UNIQUE_PRODUCTS is 100', () => {
      expect(MAX_UNIQUE_PRODUCTS).toBe(100);
    });
  
    test('CHUNK_SIZE is 25', () => {
      expect(CHUNK_SIZE).toBe(25);
    });
  
    test('MAX_BATCH_SIZE is 400', () => {
      expect(MAX_BATCH_SIZE).toBe(400);
    });
  
    test('FIRESTORE_BATCH_LIMIT is 500', () => {
      expect(FIRESTORE_BATCH_LIMIT).toBe(500);
    });
  
    test('COLLECTION_PREFIXES are correct', () => {
      expect(COLLECTION_PREFIXES.SHOP_PRODUCTS).toBe('shop_products_');
      expect(COLLECTION_PREFIXES.PRODUCTS).toBe('products_');
    });
  });
  
  // ============================================================================
  // VALIDATION TESTS
  // ============================================================================
  describe('validateProductIds', () => {
    test('returns invalid for null', () => {
      const result = validateProductIds(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_array');
    });
  
    test('returns invalid for string', () => {
      const result = validateProductIds('product123');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_array');
    });
  
    test('returns invalid for empty array', () => {
      const result = validateProductIds([]);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty_array');
    });
  
    test('returns valid for non-empty array', () => {
      const result = validateProductIds(['p1', 'p2']);
      expect(result.isValid).toBe(true);
      expect(result.count).toBe(2);
    });
  
    test('returns valid for array with one element', () => {
      const result = validateProductIds(['p1']);
      expect(result.isValid).toBe(true);
      expect(result.count).toBe(1);
    });
  });
  
  describe('validateWorkerRequest', () => {
    test('returns invalid for null', () => {
      const result = validateWorkerRequest(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for empty products', () => {
      const result = validateWorkerRequest({ products: [] });
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for products array', () => {
      const result = validateWorkerRequest({ products: [{ productId: 'p1' }] });
      expect(result.isValid).toBe(true);
      expect(result.productCount).toBe(1);
    });
  
    test('handles nested data structure', () => {
      const result = validateWorkerRequest({ data: { products: [{ productId: 'p1' }] } });
      expect(result.isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // DEDUPLICATION TESTS
  // ============================================================================
  describe('deduplicateAndCount', () => {
    test('counts single occurrences', () => {
      const result = deduplicateAndCount(['a', 'b', 'c']);
      expect(result).toHaveLength(3);
      expect(result.find((p) => p.productId === 'a').count).toBe(1);
    });
  
    test('counts duplicate occurrences', () => {
      const result = deduplicateAndCount(['a', 'a', 'b', 'a', 'b']);
      expect(result).toHaveLength(2);
      expect(result.find((p) => p.productId === 'a').count).toBe(3);
      expect(result.find((p) => p.productId === 'b').count).toBe(2);
    });
  
    test('handles empty array', () => {
      const result = deduplicateAndCount([]);
      expect(result).toHaveLength(0);
    });
  
    test('preserves order of first occurrence', () => {
      const result = deduplicateAndCount(['b', 'a', 'b', 'c']);
      expect(result[0].productId).toBe('b');
      expect(result[1].productId).toBe('a');
      expect(result[2].productId).toBe('c');
    });
  
    test('handles large duplicate count', () => {
      const ids = Array(100).fill('same_id');
      const result = deduplicateAndCount(ids);
      expect(result).toHaveLength(1);
      expect(result[0].count).toBe(100);
    });
  });
  
  describe('limitProducts', () => {
    test('returns all products if under limit', () => {
      const products = [{ productId: 'a' }, { productId: 'b' }];
      const result = limitProducts(products, 100);
      expect(result.products).toHaveLength(2);
      expect(result.trimmed).toBe(false);
    });
  
    test('trims products if over limit', () => {
      const products = Array(150).fill(null).map((_, i) => ({ productId: `p${i}` }));
      const result = limitProducts(products, 100);
      expect(result.products).toHaveLength(100);
      expect(result.trimmed).toBe(true);
      expect(result.originalCount).toBe(150);
    });
  
    test('handles exact limit', () => {
      const products = Array(100).fill(null).map((_, i) => ({ productId: `p${i}` }));
      const result = limitProducts(products, 100);
      expect(result.products).toHaveLength(100);
      expect(result.trimmed).toBe(false);
    });
  });
  
  // ============================================================================
  // CHUNKING TESTS
  // ============================================================================
  describe('chunkArray', () => {
    test('chunks array into specified size', () => {
      const arr = [1, 2, 3, 4, 5, 6, 7];
      const result = chunkArray(arr, 3);
      expect(result).toHaveLength(3);
      expect(result[0]).toEqual([1, 2, 3]);
      expect(result[1]).toEqual([4, 5, 6]);
      expect(result[2]).toEqual([7]);
    });
  
    test('handles empty array', () => {
      const result = chunkArray([], 25);
      expect(result).toHaveLength(0);
    });
  
    test('handles array smaller than chunk size', () => {
      const result = chunkArray([1, 2, 3], 25);
      expect(result).toHaveLength(1);
      expect(result[0]).toEqual([1, 2, 3]);
    });
  
    test('uses default CHUNK_SIZE', () => {
      const arr = Array(50).fill(1);
      const result = chunkArray(arr);
      expect(result).toHaveLength(2); // 50 / 25 = 2
    });
  
    test('handles exact multiple', () => {
      const arr = Array(75).fill(1);
      const result = chunkArray(arr, 25);
      expect(result).toHaveLength(3);
      expect(result[0]).toHaveLength(25);
      expect(result[1]).toHaveLength(25);
      expect(result[2]).toHaveLength(25);
    });
  });
  
  describe('calculateChunkCount', () => {
    test('calculates correct count', () => {
      expect(calculateChunkCount(100, 25)).toBe(4);
      expect(calculateChunkCount(101, 25)).toBe(5);
      expect(calculateChunkCount(25, 25)).toBe(1);
    });
  
    test('handles zero', () => {
      expect(calculateChunkCount(0, 25)).toBe(0);
    });
  });
  
  // ============================================================================
  // PRODUCT ID NORMALIZATION TESTS
  // ============================================================================
  describe('normalizeProductId', () => {
    test('normalizes shop_products prefix', () => {
      const result = normalizeProductId('shop_products_abc123');
      expect(result).toEqual({
        collection: 'shop_products',
        id: 'abc123',
      });
    });
  
    test('normalizes products prefix', () => {
      const result = normalizeProductId('products_xyz789');
      expect(result).toEqual({
        collection: 'products',
        id: 'xyz789',
      });
    });
  
    test('returns null for unknown prefix', () => {
      const result = normalizeProductId('abc123');
      expect(result).toBe(null);
    });
  
    test('returns null for null input', () => {
      expect(normalizeProductId(null)).toBe(null);
    });
  
    test('returns null for non-string', () => {
      expect(normalizeProductId(123)).toBe(null);
    });
  
    test('handles ID with underscores', () => {
      const result = normalizeProductId('shop_products_item_with_underscores');
      expect(result).toEqual({
        collection: 'shop_products',
        id: 'item_with_underscores',
      });
    });
  
    test('handles empty string after prefix', () => {
      const result = normalizeProductId('products_');
      expect(result).toEqual({
        collection: 'products',
        id: '',
      });
    });
  });
  
  describe('hasKnownPrefix', () => {
    test('returns true for known prefixes', () => {
      expect(hasKnownPrefix('shop_products_abc')).toBe(true);
      expect(hasKnownPrefix('products_xyz')).toBe(true);
    });
  
    test('returns false for unknown prefixes', () => {
      expect(hasKnownPrefix('abc123')).toBe(false);
      expect(hasKnownPrefix('other_prefix_abc')).toBe(false);
    });
  });
  
  describe('getCollectionFromId', () => {
    test('returns collection name', () => {
      expect(getCollectionFromId('shop_products_abc')).toBe('shop_products');
      expect(getCollectionFromId('products_xyz')).toBe('products');
    });
  
    test('returns null for unknown', () => {
      expect(getCollectionFromId('abc123')).toBe(null);
    });
  });
  
  // ============================================================================
  // GROUPING TESTS
  // ============================================================================
  describe('groupByCollection', () => {
    test('groups products by collection', () => {
      const products = [
        { productId: 'products_a', count: 1 },
        { productId: 'shop_products_b', count: 2 },
        { productId: 'products_c', count: 3 },
        { productId: 'unknown_id', count: 4 },
      ];
  
      const result = groupByCollection(products);
  
      expect(result.products).toHaveLength(2);
      expect(result.shop_products).toHaveLength(1);
      expect(result.unknown).toHaveLength(1);
    });
  
    test('extracts clean IDs', () => {
      const products = [{ productId: 'products_abc123', count: 1 }];
      const result = groupByCollection(products);
  
      expect(result.products[0].id).toBe('abc123');
      expect(result.products[0].count).toBe(1);
    });
  
    test('handles empty array', () => {
      const result = groupByCollection([]);
      expect(result.products).toHaveLength(0);
      expect(result.shop_products).toHaveLength(0);
      expect(result.unknown).toHaveLength(0);
    });
  });
  
  describe('countByCollection', () => {
    test('counts products per collection', () => {
      const groups = {
        products: [{ id: 'a' }, { id: 'b' }],
        shop_products: [{ id: 'c' }],
        unknown: [{ id: 'd' }, { id: 'e' }, { id: 'f' }],
      };
  
      const result = countByCollection(groups);
  
      expect(result.products).toBe(2);
      expect(result.shop_products).toBe(1);
      expect(result.unknown).toBe(3);
      expect(result.total).toBe(6);
    });
  });
  
  // ============================================================================
  // AGE GROUP TESTS
  // ============================================================================
  describe('getAgeGroup', () => {
    test('returns unknown for null', () => {
      expect(getAgeGroup(null)).toBe('unknown');
    });
  
    test('returns unknown for undefined', () => {
      expect(getAgeGroup(undefined)).toBe('unknown');
    });
  
    test('returns unknown for 0', () => {
      expect(getAgeGroup(0)).toBe('unknown');
    });
  
    test('returns under18 for age < 18', () => {
      expect(getAgeGroup(10)).toBe('under18');
      expect(getAgeGroup(17)).toBe('under18');
    });
  
    test('returns 18-24 for age 18-24', () => {
      expect(getAgeGroup(18)).toBe('18-24');
      expect(getAgeGroup(24)).toBe('18-24');
    });
  
    test('returns 25-34 for age 25-34', () => {
      expect(getAgeGroup(25)).toBe('25-34');
      expect(getAgeGroup(34)).toBe('25-34');
    });
  
    test('returns 35-44 for age 35-44', () => {
      expect(getAgeGroup(35)).toBe('35-44');
      expect(getAgeGroup(44)).toBe('35-44');
    });
  
    test('returns 45-54 for age 45-54', () => {
      expect(getAgeGroup(45)).toBe('45-54');
      expect(getAgeGroup(54)).toBe('45-54');
    });
  
    test('returns 55plus for age >= 55', () => {
      expect(getAgeGroup(55)).toBe('55plus');
      expect(getAgeGroup(100)).toBe('55plus');
    });
  });
  
  describe('getAllAgeGroups', () => {
    test('returns all age groups', () => {
      const groups = getAllAgeGroups();
      expect(groups).toContain('unknown');
      expect(groups).toContain('under18');
      expect(groups).toContain('18-24');
      expect(groups).toContain('55plus');
    });
  });
  
  describe('isValidAgeGroup', () => {
    test('returns true for valid groups', () => {
      expect(isValidAgeGroup('unknown')).toBe(true);
      expect(isValidAgeGroup('18-24')).toBe(true);
    });
  
    test('returns false for invalid groups', () => {
      expect(isValidAgeGroup('invalid')).toBe(false);
      expect(isValidAgeGroup('18-25')).toBe(false);
    });
  });
  
  // ============================================================================
  // GENDER TESTS
  // ============================================================================
  describe('normalizeGender', () => {
    test('lowercases gender', () => {
      expect(normalizeGender('Male')).toBe('male');
      expect(normalizeGender('FEMALE')).toBe('female');
    });
  
    test('returns unknown for null', () => {
      expect(normalizeGender(null)).toBe('unknown');
    });
  
    test('returns unknown for undefined', () => {
      expect(normalizeGender(undefined)).toBe('unknown');
    });
  
    test('returns unknown for empty string', () => {
      expect(normalizeGender('')).toBe('unknown');
    });
  });
  
  // ============================================================================
  // BOOSTED PRODUCT TESTS
  // ============================================================================
  describe('isBoostedProduct', () => {
    test('returns true for boosted product with start time', () => {
      expect(isBoostedProduct({ isBoosted: true, boostStartTime: Date.now() })).toBe(true);
    });
  
    test('returns false if not boosted', () => {
      expect(isBoostedProduct({ isBoosted: false, boostStartTime: Date.now() })).toBe(false);
    });
  
    test('returns false if no start time', () => {
      expect(isBoostedProduct({ isBoosted: true })).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isBoostedProduct(null)).toBe(false);
    });
  });
  
  describe('classifyProducts', () => {
    test('classifies boosted shop products', () => {
      const products = [
        {
          ref: { id: 'p1' },
          data: { isBoosted: true, boostStartTime: Date.now(), shopId: 'shop1' },
          collection: 'shop_products',
          count: 2,
        },
      ];
  
      const result = classifyProducts(products);
  
      expect(result.boostedShopProducts['shop1']).toHaveLength(1);
      expect(result.regularProducts).toHaveLength(0);
    });
  
    test('classifies boosted user products', () => {
      const products = [
        {
          ref: { id: 'p1' },
          data: { isBoosted: true, boostStartTime: Date.now(), userId: 'user1' },
          collection: 'products',
          count: 3,
        },
      ];
  
      const result = classifyProducts(products);
  
      expect(result.boostedUserProducts['user1']).toHaveLength(1);
      expect(result.regularProducts).toHaveLength(0);
    });
  
    test('classifies regular products', () => {
      const products = [
        {
          ref: { id: 'p1' },
          data: { isBoosted: false },
          collection: 'products',
          count: 1,
        },
      ];
  
      const result = classifyProducts(products);
  
      expect(result.regularProducts).toHaveLength(1);
      expect(result.regularProducts[0].isBoosted).toBe(false);
    });
  
    test('handles boosted without owner as regular', () => {
      const products = [
        {
          ref: { id: 'p1' },
          data: { isBoosted: true, boostStartTime: Date.now() }, // No shopId or userId
          collection: 'products',
          count: 1,
        },
      ];
  
      const result = classifyProducts(products);
  
      expect(result.regularProducts).toHaveLength(1);
      expect(result.regularProducts[0].isBoosted).toBe(true);
    });
  });
  
  // ============================================================================
  // BATCH MANAGEMENT TESTS
  // ============================================================================
  describe('shouldCommitBatch', () => {
    test('returns true when at max', () => {
      expect(shouldCommitBatch(400)).toBe(true);
    });
  
    test('returns true when over max', () => {
      expect(shouldCommitBatch(450)).toBe(true);
    });
  
    test('returns false when under max', () => {
      expect(shouldCommitBatch(399)).toBe(false);
    });
  
    test('respects custom max', () => {
      expect(shouldCommitBatch(200, 200)).toBe(true);
      expect(shouldCommitBatch(199, 200)).toBe(false);
    });
  });
  
  describe('calculateOperationsNeeded', () => {
    test('calculates product operations', () => {
      expect(calculateOperationsNeeded(10)).toBe(10);
    });
  
    test('adds boost history operations', () => {
      expect(calculateOperationsNeeded(10, 5)).toBe(15);
    });
  });
  
  describe('willFitInBatch', () => {
    test('returns true if will fit', () => {
      expect(willFitInBatch(350, 50)).toBe(true);
    });
  
    test('returns false if will not fit', () => {
      expect(willFitInBatch(350, 51)).toBe(false);
    });
  
    test('returns true for exact fit', () => {
      expect(willFitInBatch(350, 50)).toBe(true);
    });
  });
  
  // ============================================================================
  // FIELD PATHS TESTS
  // ============================================================================
  describe('buildDemographicsPath', () => {
    test('builds correct path', () => {
      expect(buildDemographicsPath('male')).toBe('demographics.male');
      expect(buildDemographicsPath('female')).toBe('demographics.female');
    });
  });
  
  describe('buildAgeGroupPath', () => {
    test('builds correct path', () => {
      expect(buildAgeGroupPath('18-24')).toBe('viewerAgeGroups.18-24');
      expect(buildAgeGroupPath('55plus')).toBe('viewerAgeGroups.55plus');
    });
  });
  
  // ============================================================================
  // RESPONSE TESTS
  // ============================================================================
  describe('buildSuccessResponse', () => {
    test('builds correct response', () => {
      const result = buildSuccessResponse(4, 100);
  
      expect(result.success).toBe(true);
      expect(result.queued).toBe(4);
      expect(result.totalImpressions).toBe(100);
      expect(result.message).toBe('Impressions are being recorded');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete impression processing flow', () => {
      // 1. User views 10 products (with duplicates)
      const productIds = [
        'products_a', 'products_a', 'products_b',
        'shop_products_c', 'shop_products_c', 'shop_products_c',
        'products_d', 'unknown_id',
      ];
  
      // 2. Validate
      const validation = validateProductIds(productIds);
      expect(validation.isValid).toBe(true);
  
      // 3. Deduplicate and count
      const deduplicated = deduplicateAndCount(productIds);
      expect(deduplicated.find((p) => p.productId === 'products_a').count).toBe(2);
      expect(deduplicated.find((p) => p.productId === 'shop_products_c').count).toBe(3);
  
      // 4. Limit (not needed here)
      const limited = limitProducts(deduplicated);
      expect(limited.trimmed).toBe(false);
  
      // 5. Chunk for Cloud Tasks
      const chunks = chunkArray(limited.products, 25);
      expect(chunks).toHaveLength(1); // 4 unique products
  
      // 6. Group by collection in worker
      const groups = groupByCollection(deduplicated);
      expect(groups.products).toHaveLength(3);
      expect(groups.shop_products).toHaveLength(1); // c
      expect(groups.unknown).toHaveLength(1); // unknown_id
    });
  
    test('large batch handling', () => {
      // User views 200 unique products
      const productIds = Array(200).fill(null).map((_, i) => `products_${i}`);
  
      const deduplicated = deduplicateAndCount(productIds);
      expect(deduplicated).toHaveLength(200);
  
      const limited = limitProducts(deduplicated);
      expect(limited.trimmed).toBe(true);
      expect(limited.products).toHaveLength(100);
  
      const chunks = chunkArray(limited.products, 25);
      expect(chunks).toHaveLength(4);
    });
  
    test('boosted product classification', () => {
      const resolvedProducts = [
        {
          ref: { id: 'p1' },
          data: { isBoosted: true, boostStartTime: 123, shopId: 'shop1' },
          collection: 'shop_products',
          count: 5,
        },
        {
          ref: { id: 'p2' },
          data: { isBoosted: true, boostStartTime: 456, userId: 'user1' },
          collection: 'products',
          count: 3,
        },
        {
          ref: { id: 'p3' },
          data: { isBoosted: false },
          collection: 'products',
          count: 1,
        },
      ];
  
      const classified = classifyProducts(resolvedProducts);
  
      expect(Object.keys(classified.boostedShopProducts)).toHaveLength(1);
      expect(Object.keys(classified.boostedUserProducts)).toHaveLength(1);
      expect(classified.regularProducts).toHaveLength(1);
    });
  
    test('demographics tracking', () => {
      const gender = normalizeGender('Female');
      const ageGroup = getAgeGroup(28);
  
      const genderPath = buildDemographicsPath(gender);
      const agePath = buildAgeGroupPath(ageGroup);
  
      expect(gender).toBe('female');
      expect(ageGroup).toBe('25-34');
      expect(genderPath).toBe('demographics.female');
      expect(agePath).toBe('viewerAgeGroups.25-34');
    });
  
    test('batch size management', () => {
      let operationCount = 0;
  
      // Simulate processing 500 products
      for (let i = 0; i < 500; i++) {
        if (shouldCommitBatch(operationCount)) {
          // Would commit batch here
          operationCount = 0;
        }
        operationCount++;
      }
  
      // Should have committed at least once
      expect(operationCount).toBeLessThan(MAX_BATCH_SIZE);
    });
  });

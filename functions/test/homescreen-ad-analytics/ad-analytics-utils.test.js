// functions/test/homescreen-ad-analytics/ad-analytics-utils.test.js
//
// Unit tests for ad analytics utility functions
// Tests the EXACT logic from ad analytics cloud functions
//
// Run: npx jest test/homescreen-ad-analytics/ad-analytics-utils.test.js

const {
    // Age calculation
    calculateAge,
    calculateAgeFromDate,
  
    // Age groups

    getAgeGroup,
    getAllAgeGroups,
    isValidAgeGroup,
  
    // Gender
 
    normalizeGender,
    isValidGender,
  
    // Request validation
    validateTrackClickRequest,
    validateTrackConversionRequest,
    validateAnalyticsRequest,
  
    // Conversion
    isConversion,
    getAttributionWindowMs,
    isWithinAttributionWindow,
  
    // Conversion rate
    calculateConversionRate,
    calculateConversionRatePrecise,
  
    // Demographics
    createEmptyDemographics,
    getGenderFieldPath,
    getAgeGroupFieldPath,
    mergeDemographics,
  
    // Snapshot
    getSnapshotDate,
    getSnapshotDocId,
  
    // Ad collections

    getAdCollectionName,
    getAllAdCollectionNames,
  
    // Data builders
    buildAnalyticsData,
    buildClickRecord,
  } = require('./ad-analytics-utils');
  
  // ============================================================================
  // HELPER: Create mock Firestore Timestamp
  // ============================================================================
  function createMockTimestamp(date) {
    return {
      toDate: () => date,
    };
  }
  
  // ============================================================================
  // AGE CALCULATION TESTS
  // ============================================================================
  describe('calculateAge', () => {
    const today = new Date('2024-06-15');
  
    test('returns null for null birthDate', () => {
      expect(calculateAge(null, today)).toBe(null);
    });
  
    test('returns null for undefined birthDate', () => {
      expect(calculateAge(undefined, today)).toBe(null);
    });
  
    test('returns null if birthDate has no toDate method', () => {
      expect(calculateAge({ date: '2000-01-01' }, today)).toBe(null);
    });
  
    test('calculates correct age when birthday has passed', () => {
      const birthDate = createMockTimestamp(new Date('2000-01-15')); // Jan 15
      const result = calculateAge(birthDate, today); // June 15
      expect(result).toBe(24);
    });
  
    test('calculates correct age when birthday has not passed (same month)', () => {
      const birthDate = createMockTimestamp(new Date('2000-06-20')); // June 20
      const result = calculateAge(birthDate, today); // June 15
      expect(result).toBe(23); // Not yet 24
    });
  
    test('calculates correct age when birthday is today', () => {
      const birthDate = createMockTimestamp(new Date('2000-06-15')); // June 15
      const result = calculateAge(birthDate, today); // June 15
      expect(result).toBe(24);
    });
  
    test('calculates correct age when birthday is tomorrow', () => {
      const birthDate = createMockTimestamp(new Date('2000-06-16')); // June 16
      const result = calculateAge(birthDate, today); // June 15
      expect(result).toBe(23); // Not yet 24
    });
  
    test('calculates correct age for December birthday in January', () => {
      const january = new Date('2024-01-15');
      const birthDate = createMockTimestamp(new Date('2000-12-20'));
      const result = calculateAge(birthDate, january);
      expect(result).toBe(23); // December birthday not passed yet
    });
  
    test('handles leap year birthdays', () => {
      const birthDate = createMockTimestamp(new Date('2000-02-29'));
      const march1 = new Date('2024-03-01');
      const result = calculateAge(birthDate, march1);
      expect(result).toBe(24);
    });
  });
  
  describe('calculateAgeFromDate', () => {
    const today = new Date('2024-06-15');
  
    test('returns null for null date', () => {
      expect(calculateAgeFromDate(null, today)).toBe(null);
    });
  
    test('returns null for non-Date object', () => {
      expect(calculateAgeFromDate('2000-01-01', today)).toBe(null);
    });
  
    test('calculates correct age', () => {
      const birthDate = new Date('2000-01-15');
      expect(calculateAgeFromDate(birthDate, today)).toBe(24);
    });
  });
  
  // ============================================================================
  // AGE GROUP TESTS
  // ============================================================================
  describe('getAgeGroup', () => {
    test('returns Unknown for null', () => {
      expect(getAgeGroup(null)).toBe('Unknown');
    });
  
    test('returns Unknown for undefined', () => {
      expect(getAgeGroup(undefined)).toBe('Unknown');
    });
  
    test('returns Unknown for negative age', () => {
      expect(getAgeGroup(-5)).toBe('Unknown');
    });
  
    test('returns Unknown for zero', () => {
      expect(getAgeGroup(0)).toBe('Unknown');
    });
  
    test('returns Under 18 for age 10', () => {
      expect(getAgeGroup(10)).toBe('Under 18');
    });
  
    test('returns Under 18 for age 17', () => {
      expect(getAgeGroup(17)).toBe('Under 18');
    });
  
    test('returns 18-24 for age 18', () => {
      expect(getAgeGroup(18)).toBe('18-24');
    });
  
    test('returns 18-24 for age 24', () => {
      expect(getAgeGroup(24)).toBe('18-24');
    });
  
    test('returns 25-34 for age 25', () => {
      expect(getAgeGroup(25)).toBe('25-34');
    });
  
    test('returns 25-34 for age 34', () => {
      expect(getAgeGroup(34)).toBe('25-34');
    });
  
    test('returns 35-44 for age 35', () => {
      expect(getAgeGroup(35)).toBe('35-44');
    });
  
    test('returns 45-54 for age 45', () => {
      expect(getAgeGroup(45)).toBe('45-54');
    });
  
    test('returns 55-64 for age 55', () => {
      expect(getAgeGroup(55)).toBe('55-64');
    });
  
    test('returns 65+ for age 65', () => {
      expect(getAgeGroup(65)).toBe('65+');
    });
  
    test('returns 65+ for age 100', () => {
      expect(getAgeGroup(100)).toBe('65+');
    });
  });
  
  describe('getAllAgeGroups', () => {
    test('returns all age groups', () => {
      const groups = getAllAgeGroups();
      expect(groups).toContain('Unknown');
      expect(groups).toContain('Under 18');
      expect(groups).toContain('18-24');
      expect(groups).toContain('25-34');
      expect(groups).toContain('35-44');
      expect(groups).toContain('45-54');
      expect(groups).toContain('55-64');
      expect(groups).toContain('65+');
      expect(groups.length).toBe(8);
    });
  });
  
  describe('isValidAgeGroup', () => {
    test('returns true for valid age groups', () => {
      expect(isValidAgeGroup('Unknown')).toBe(true);
      expect(isValidAgeGroup('18-24')).toBe(true);
      expect(isValidAgeGroup('65+')).toBe(true);
    });
  
    test('returns false for invalid age groups', () => {
      expect(isValidAgeGroup('invalid')).toBe(false);
      expect(isValidAgeGroup('18-25')).toBe(false);
      expect(isValidAgeGroup('')).toBe(false);
    });
  });
  
  // ============================================================================
  // GENDER TESTS
  // ============================================================================
  describe('normalizeGender', () => {
    test('returns Not specified for null', () => {
      expect(normalizeGender(null)).toBe('Not specified');
    });
  
    test('returns Not specified for undefined', () => {
      expect(normalizeGender(undefined)).toBe('Not specified');
    });
  
    test('returns Not specified for empty string', () => {
      expect(normalizeGender('')).toBe('Not specified');
    });
  
    test('returns Male for Male', () => {
      expect(normalizeGender('Male')).toBe('Male');
    });
  
    test('returns Male for lowercase male', () => {
      expect(normalizeGender('male')).toBe('Male');
    });
  
    test('returns Male for m', () => {
      expect(normalizeGender('m')).toBe('Male');
    });
  
    test('returns Female for Female', () => {
      expect(normalizeGender('Female')).toBe('Female');
    });
  
    test('returns Female for lowercase female', () => {
      expect(normalizeGender('female')).toBe('Female');
    });
  
    test('returns Female for f', () => {
      expect(normalizeGender('f')).toBe('Female');
    });
  
    test('returns Other for Other', () => {
      expect(normalizeGender('Other')).toBe('Other');
    });
  
    test('returns Other for lowercase other', () => {
      expect(normalizeGender('other')).toBe('Other');
    });
  
    test('returns Not specified for unknown value', () => {
      expect(normalizeGender('unknown')).toBe('Not specified');
    });
  
    test('trims whitespace', () => {
      expect(normalizeGender('  Male  ')).toBe('Male');
    });
  });
  
  describe('isValidGender', () => {
    test('returns true for valid genders', () => {
      expect(isValidGender('Male')).toBe(true);
      expect(isValidGender('Female')).toBe(true);
      expect(isValidGender('Other')).toBe(true);
      expect(isValidGender('Not specified')).toBe(true);
    });
  
    test('returns false for invalid genders', () => {
      expect(isValidGender('male')).toBe(false); // Case matters for validation
      expect(isValidGender('invalid')).toBe(false);
      expect(isValidGender('')).toBe(false);
    });
  });
  
  // ============================================================================
  // REQUEST VALIDATION TESTS
  // ============================================================================
  describe('validateTrackClickRequest', () => {
    test('returns invalid for null request', () => {
      const result = validateTrackClickRequest(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for missing adId', () => {
      const result = validateTrackClickRequest({ adType: 'topBanner' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_ad_id');
    });
  
    test('returns invalid for missing adType', () => {
      const result = validateTrackClickRequest({ adId: 'ad123' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_ad_type');
    });
  
    test('returns valid for complete request', () => {
      const result = validateTrackClickRequest({ adId: 'ad123', adType: 'topBanner' });
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('validateTrackConversionRequest', () => {
    test('returns invalid for null request', () => {
      const result = validateTrackConversionRequest(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for missing orderId', () => {
      const result = validateTrackConversionRequest({ productIds: ['p1'] });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_order_id');
    });
  
    test('returns invalid for missing productIds', () => {
      const result = validateTrackConversionRequest({ orderId: 'order123' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_product_ids');
    });
  
    test('returns invalid for non-array productIds', () => {
      const result = validateTrackConversionRequest({ orderId: 'order123', productIds: 'p1' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_product_ids');
    });
  
    test('returns invalid for empty productIds array', () => {
      const result = validateTrackConversionRequest({ orderId: 'order123', productIds: [] });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty_product_ids');
    });
  
    test('returns valid for complete request', () => {
      const result = validateTrackConversionRequest({ orderId: 'order123', productIds: ['p1', 'p2'] });
      expect(result.isValid).toBe(true);
      expect(result.productCount).toBe(2);
    });
  });
  
  describe('validateAnalyticsRequest', () => {
    test('returns invalid for missing adId', () => {
      const result = validateAnalyticsRequest({ userId: 'user123' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_ad_id');
    });
  
    test('returns invalid for missing userId', () => {
      const result = validateAnalyticsRequest({ adId: 'ad123' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_user_id');
    });
  
    test('returns valid for complete request', () => {
      const result = validateAnalyticsRequest({ adId: 'ad123', userId: 'user123' });
      expect(result.isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // CONVERSION TESTS
  // ============================================================================
  describe('isConversion', () => {
    test('returns false for null clickData', () => {
      expect(isConversion(null, ['p1'], ['s1'])).toBe(false);
    });
  
    test('returns false for missing linkedType', () => {
      expect(isConversion({ linkedId: 'p1' }, ['p1'], ['s1'])).toBe(false);
    });
  
    test('returns false for missing linkedId', () => {
      expect(isConversion({ linkedType: 'product' }, ['p1'], ['s1'])).toBe(false);
    });
  
    test('returns true for matching product', () => {
      const clickData = { linkedType: 'product', linkedId: 'p1' };
      expect(isConversion(clickData, ['p1', 'p2'], null)).toBe(true);
    });
  
    test('returns false for non-matching product', () => {
      const clickData = { linkedType: 'product', linkedId: 'p3' };
      expect(isConversion(clickData, ['p1', 'p2'], null)).toBe(false);
    });
  
    test('returns true for matching shop', () => {
      const clickData = { linkedType: 'shop', linkedId: 's1' };
      expect(isConversion(clickData, ['p1'], ['s1', 's2'])).toBe(true);
    });
  
    test('returns false for non-matching shop', () => {
      const clickData = { linkedType: 'shop', linkedId: 's3' };
      expect(isConversion(clickData, ['p1'], ['s1', 's2'])).toBe(false);
    });
  
    test('returns false for shop type with null shopIds', () => {
      const clickData = { linkedType: 'shop', linkedId: 's1' };
      expect(isConversion(clickData, ['p1'], null)).toBe(false);
    });
  });
  
  describe('getAttributionWindowMs', () => {
    test('returns 30 days in ms by default', () => {
      expect(getAttributionWindowMs()).toBe(30 * 24 * 60 * 60 * 1000);
    });
  
    test('returns custom days in ms', () => {
      expect(getAttributionWindowMs(7)).toBe(7 * 24 * 60 * 60 * 1000);
    });
  });
  
  describe('isWithinAttributionWindow', () => {
    const clickTime = 1000000000000; // Some timestamp
  
    test('returns true if conversion is same time as click', () => {
      expect(isWithinAttributionWindow(clickTime, clickTime, 30)).toBe(true);
    });
  
    test('returns true if conversion is within window', () => {
      const conversionTime = clickTime + (15 * 24 * 60 * 60 * 1000); // 15 days later
      expect(isWithinAttributionWindow(clickTime, conversionTime, 30)).toBe(true);
    });
  
    test('returns true if conversion is exactly at window boundary', () => {
      const conversionTime = clickTime + (30 * 24 * 60 * 60 * 1000); // 30 days later
      expect(isWithinAttributionWindow(clickTime, conversionTime, 30)).toBe(true);
    });
  
    test('returns false if conversion is after window', () => {
      const conversionTime = clickTime + (31 * 24 * 60 * 60 * 1000); // 31 days later
      expect(isWithinAttributionWindow(clickTime, conversionTime, 30)).toBe(false);
    });
  });
  
  // ============================================================================
  // CONVERSION RATE TESTS
  // ============================================================================
  describe('calculateConversionRate', () => {
    test('returns 0 for zero clicks', () => {
      expect(calculateConversionRate(0, 10)).toBe(0);
    });
  
    test('returns 0 for null clicks', () => {
      expect(calculateConversionRate(null, 10)).toBe(0);
    });
  
    test('returns 0 for negative clicks', () => {
      expect(calculateConversionRate(-5, 10)).toBe(0);
    });
  
    test('calculates correct percentage', () => {
      expect(calculateConversionRate(100, 10)).toBe(10); // 10%
    });
  
    test('handles zero conversions', () => {
      expect(calculateConversionRate(100, 0)).toBe(0);
    });
  
    test('handles null conversions', () => {
      expect(calculateConversionRate(100, null)).toBe(0);
    });
  
    test('calculates 100% rate', () => {
      expect(calculateConversionRate(50, 50)).toBe(100);
    });
  
    test('handles decimal results', () => {
      expect(calculateConversionRate(3, 1)).toBeCloseTo(33.333, 2);
    });
  });
  
  describe('calculateConversionRatePrecise', () => {
    test('rounds to 2 decimal places by default', () => {
      expect(calculateConversionRatePrecise(3, 1)).toBe(33.33);
    });
  
    test('rounds to custom precision', () => {
      expect(calculateConversionRatePrecise(3, 1, 1)).toBe(33.3);
      expect(calculateConversionRatePrecise(3, 1, 0)).toBe(33);
    });
  });
  
  // ============================================================================
  // DEMOGRAPHICS TESTS
  // ============================================================================
  describe('createEmptyDemographics', () => {
    test('returns empty structure', () => {
      const result = createEmptyDemographics();
      expect(result).toEqual({
        gender: {},
        ageGroups: {},
      });
    });
  });
  
  describe('getGenderFieldPath', () => {
    test('returns correct path for Male', () => {
      expect(getGenderFieldPath('Male')).toBe('demographics.gender.Male');
    });
  
    test('returns correct path for Female', () => {
      expect(getGenderFieldPath('Female')).toBe('demographics.gender.Female');
    });
  });
  
  describe('getAgeGroupFieldPath', () => {
    test('returns correct path for 18-24', () => {
      expect(getAgeGroupFieldPath('18-24')).toBe('demographics.ageGroups.18-24');
    });
  
    test('returns correct path for 65+', () => {
      expect(getAgeGroupFieldPath('65+')).toBe('demographics.ageGroups.65+');
    });
  });
  
  describe('mergeDemographics', () => {
    test('adds to empty demographics', () => {
      const result = mergeDemographics({}, 'Male', '25-34');
      expect(result).toEqual({
        gender: { Male: 1 },
        ageGroups: { '25-34': 1 },
      });
    });
  
    test('increments existing counts', () => {
      const existing = {
        gender: { Male: 5 },
        ageGroups: { '25-34': 3 },
      };
      const result = mergeDemographics(existing, 'Male', '25-34');
      expect(result).toEqual({
        gender: { Male: 6 },
        ageGroups: { '25-34': 4 },
      });
    });
  
    test('adds new demographics to existing', () => {
      const existing = {
        gender: { Male: 5 },
        ageGroups: { '25-34': 3 },
      };
      const result = mergeDemographics(existing, 'Female', '18-24');
      expect(result).toEqual({
        gender: { Male: 5, Female: 1 },
        ageGroups: { '25-34': 3, '18-24': 1 },
      });
    });
  
    test('handles null existing demographics', () => {
      const result = mergeDemographics(null, 'Male', '25-34');
      expect(result).toEqual({
        gender: { Male: 1 },
        ageGroups: { '25-34': 1 },
      });
    });
  });
  
  // ============================================================================
  // SNAPSHOT TESTS
  // ============================================================================
  describe('getSnapshotDate', () => {
    test('returns start of day', () => {
      const input = new Date('2024-06-15T14:30:45Z');
      const result = getSnapshotDate(input);
      expect(result.getHours()).toBe(0);
      expect(result.getMinutes()).toBe(0);
      expect(result.getSeconds()).toBe(0);
    });
  
    test('preserves year, month, day', () => {
      const input = new Date('2024-06-15T14:30:45Z');
      const result = getSnapshotDate(input);
      expect(result.getFullYear()).toBe(2024);
      expect(result.getMonth()).toBe(5); // June is 5
      expect(result.getDate()).toBe(15);
    });
  });
  
  describe('getSnapshotDocId', () => {
    test('returns YYYY-MM-DD format', () => {
      const input = new Date('2024-06-15T14:30:45Z');
      const result = getSnapshotDocId(input);
      expect(result).toBe('2024-06-15');
    });
  
    test('pads single digit month and day', () => {
      const input = new Date('2024-01-05T00:00:00Z');
      const result = getSnapshotDocId(input);
      expect(result).toBe('2024-01-05');
    });
  });
  
  // ============================================================================
  // AD COLLECTION TESTS
  // ============================================================================
  describe('getAdCollectionName', () => {
    test('returns correct collection for topBanner', () => {
      expect(getAdCollectionName('topBanner')).toBe('market_top_ads_banners');
    });
  
    test('returns correct collection for thinBanner', () => {
      expect(getAdCollectionName('thinBanner')).toBe('market_thin_banners');
    });
  
    test('returns correct collection for marketBanner', () => {
      expect(getAdCollectionName('marketBanner')).toBe('market_banners');
    });
  
    test('returns default for unknown type', () => {
      expect(getAdCollectionName('unknown')).toBe('market_banners');
    });
  });
  
  describe('getAllAdCollectionNames', () => {
    test('returns all collection names', () => {
      const collections = getAllAdCollectionNames();
      expect(collections).toContain('market_top_ads_banners');
      expect(collections).toContain('market_thin_banners');
      expect(collections).toContain('market_banners');
      expect(collections.length).toBe(3);
    });
  });
  
  // ============================================================================
  // DATA BUILDER TESTS
  // ============================================================================
  describe('buildAnalyticsData', () => {
    test('builds complete analytics data', () => {
      const params = {
        adId: 'ad123',
        adType: 'topBanner',
        userId: 'user456',
        gender: 'Male',
        age: 25,
        ageGroup: '25-34',
        linkedType: 'product',
        linkedId: 'prod789',
      };
  
      const result = buildAnalyticsData(params);
  
      expect(result.adId).toBe('ad123');
      expect(result.adType).toBe('topBanner');
      expect(result.userId).toBe('user456');
      expect(result.gender).toBe('Male');
      expect(result.age).toBe(25);
      expect(result.ageGroup).toBe('25-34');
      expect(result.linkedType).toBe('product');
      expect(result.linkedId).toBe('prod789');
      expect(result.eventType).toBe('click');
      expect(typeof result.timestamp).toBe('number');
    });
  
    test('uses defaults for missing optional fields', () => {
      const result = buildAnalyticsData({ adId: 'ad123', adType: 'topBanner', userId: 'user456' });
  
      expect(result.gender).toBe('Not specified');
      expect(result.age).toBe(null);
      expect(result.ageGroup).toBe('Unknown');
      expect(result.linkedType).toBe(null);
      expect(result.linkedId).toBe(null);
    });
  });
  
  describe('buildClickRecord', () => {
    test('builds complete click record', () => {
      const params = {
        userId: 'user123',
        gender: 'Female',
        age: 30,
        ageGroup: '25-34',
        linkedType: 'shop',
        linkedId: 'shop456',
      };
  
      const result = buildClickRecord(params);
  
      expect(result.userId).toBe('user123');
      expect(result.gender).toBe('Female');
      expect(result.age).toBe(30);
      expect(result.ageGroup).toBe('25-34');
      expect(result.linkedType).toBe('shop');
      expect(result.linkedId).toBe('shop456');
      expect(result.converted).toBe(false);
    });
  
    test('uses defaults for missing fields', () => {
      const result = buildClickRecord({ userId: 'user123' });
  
      expect(result.gender).toBe('Not specified');
      expect(result.age).toBe(null);
      expect(result.ageGroup).toBe('Unknown');
      expect(result.converted).toBe(false);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete user click tracking flow', () => {
      // 1. User has birthdate
      const birthDate = createMockTimestamp(new Date('1990-03-15'));
      const today = new Date('2024-06-15');
      const age = calculateAge(birthDate, today);
      expect(age).toBe(34);
  
      // 2. Get age group
      const ageGroup = getAgeGroup(age);
      expect(ageGroup).toBe('25-34');
  
      // 3. Normalize gender
      const gender = normalizeGender('male');
      expect(gender).toBe('Male');
  
      // 4. Validate click request
      const requestResult = validateTrackClickRequest({ adId: 'ad123', adType: 'topBanner' });
      expect(requestResult.isValid).toBe(true);
  
      // 5. Build analytics data
      const analyticsData = buildAnalyticsData({
        adId: 'ad123',
        adType: 'topBanner',
        userId: 'user456',
        gender,
        age,
        ageGroup,
        linkedType: 'product',
        linkedId: 'prod789',
      });
      expect(analyticsData.eventType).toBe('click');
    });
  
    test('conversion attribution flow', () => {
      // 1. User clicked on a product ad
      const clickData = {
        linkedType: 'product',
        linkedId: 'prod123',
        clickedAt: Date.now() - (7 * 24 * 60 * 60 * 1000), // 7 days ago
      };
  
      // 2. User purchased products
      const purchasedProductIds = ['prod123', 'prod456'];
  
      // 3. Check if click is a conversion
      const isConv = isConversion(clickData, purchasedProductIds, null);
      expect(isConv).toBe(true);
  
      // 4. Check if within attribution window
      const withinWindow = isWithinAttributionWindow(
        clickData.clickedAt,
        Date.now(),
        30
      );
      expect(withinWindow).toBe(true);
    });
  
    test('daily analytics snapshot creation', () => {
      // 1. Get snapshot date
      const snapshotDate = getSnapshotDate(new Date('2024-06-15T14:30:00Z'));
      expect(snapshotDate.getHours()).toBe(0);
  
      // 2. Get doc ID
      const docId = getSnapshotDocId(new Date('2024-06-15'));
      expect(docId).toBe('2024-06-15');
  
      // 3. Calculate conversion rate
      const rate = calculateConversionRatePrecise(1000, 25, 2);
      expect(rate).toBe(2.5); // 2.5%
  
      // 4. Get all collections to snapshot
      const collections = getAllAdCollectionNames();
      expect(collections.length).toBe(3);
    });
  
    test('demographics aggregation', () => {
      // Start with empty demographics
      let demographics = createEmptyDemographics();
  
      // Add several clicks
      demographics = mergeDemographics(demographics, 'Male', '25-34');
      demographics = mergeDemographics(demographics, 'Male', '25-34');
      demographics = mergeDemographics(demographics, 'Female', '18-24');
      demographics = mergeDemographics(demographics, 'Male', '35-44');
  
      expect(demographics.gender.Male).toBe(3);
      expect(demographics.gender.Female).toBe(1);
      expect(demographics.ageGroups['25-34']).toBe(2);
      expect(demographics.ageGroups['18-24']).toBe(1);
      expect(demographics.ageGroups['35-44']).toBe(1);
    });
  
    test('age group boundary testing', () => {
      // Test all boundary ages
      expect(getAgeGroup(17)).toBe('Under 18');
      expect(getAgeGroup(18)).toBe('18-24');
      expect(getAgeGroup(24)).toBe('18-24');
      expect(getAgeGroup(25)).toBe('25-34');
      expect(getAgeGroup(34)).toBe('25-34');
      expect(getAgeGroup(35)).toBe('35-44');
      expect(getAgeGroup(44)).toBe('35-44');
      expect(getAgeGroup(45)).toBe('45-54');
      expect(getAgeGroup(54)).toBe('45-54');
      expect(getAgeGroup(55)).toBe('55-64');
      expect(getAgeGroup(64)).toBe('55-64');
      expect(getAgeGroup(65)).toBe('65+');
    });
  });

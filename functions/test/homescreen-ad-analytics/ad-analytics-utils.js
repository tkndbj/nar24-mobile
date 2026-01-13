// functions/test/homescreen-ad-analytics/ad-analytics-utils.js
//
// EXTRACTED PURE LOGIC from ad analytics cloud functions
// These functions are EXACT COPIES of logic from the analytics functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source analytics functions.

// ============================================================================
// AGE CALCULATION
// Mirrors: calculateAge() in ad analytics functions
// ============================================================================

function calculateAge(birthDate, today = new Date()) {
    if (!birthDate || typeof birthDate.toDate !== 'function') return null;
  
    const birth = birthDate.toDate();
    let age = today.getFullYear() - birth.getFullYear();
    const monthDiff = today.getMonth() - birth.getMonth();
  
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
      age--;
    }
  
    return age;
  }
  
 
  function calculateAgeFromDate(birthDate, today = new Date()) {
    if (!birthDate || !(birthDate instanceof Date)) return null;
  
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();
  
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
      age--;
    }
  
    return age;
  }
  
  // ============================================================================
  // AGE GROUP MAPPING
  // Mirrors: getAgeGroup() in ad analytics functions
  // ============================================================================
  
  /**
   * Age group boundaries
   */
  const AGE_GROUP_BOUNDARIES = [
    { max: 18, label: 'Under 18' },
    { max: 25, label: '18-24' },
    { max: 35, label: '25-34' },
    { max: 45, label: '35-44' },
    { max: 55, label: '45-54' },
    { max: 65, label: '55-64' },
    { max: Infinity, label: '65+' },
  ];

  function getAgeGroup(age) {
    if (!age || age < 0) return 'Unknown';
    if (age < 18) return 'Under 18';
    if (age < 25) return '18-24';
    if (age < 35) return '25-34';
    if (age < 45) return '35-44';
    if (age < 55) return '45-54';
    if (age < 65) return '55-64';
    return '65+';
  }

  function getAllAgeGroups() {
    return ['Unknown', 'Under 18', '18-24', '25-34', '35-44', '45-54', '55-64', '65+'];
  }

  function isValidAgeGroup(ageGroup) {
    return getAllAgeGroups().includes(ageGroup);
  }
  
  // ============================================================================
  // GENDER HANDLING
  // Mirrors: gender handling in analytics functions
  // ============================================================================
  
  /**
   * Valid gender values for analytics
   */
  const VALID_GENDERS = ['Male', 'Female', 'Other', 'Not specified'];
 
  function normalizeGender(gender) {
    if (!gender || typeof gender !== 'string') return 'Not specified';
    
    const normalized = gender.trim();
    if (VALID_GENDERS.includes(normalized)) {
      return normalized;
    }
    
    // Handle common variations
    const lower = normalized.toLowerCase();
    if (lower === 'male' || lower === 'm') return 'Male';
    if (lower === 'female' || lower === 'f') return 'Female';
    if (lower === 'other') return 'Other';
    
    return 'Not specified';
  }

  function isValidGender(gender) {
    return VALID_GENDERS.includes(gender);
  }
  
  // ============================================================================
  // TRACKING REQUEST VALIDATION
  // Mirrors: validation in trackAdClick
  // ============================================================================

  function validateTrackClickRequest(requestData) {
    const { adId, adType } = requestData || {};
  
    if (!adId) {
      return {
        isValid: false,
        reason: 'missing_ad_id',
        message: 'adId is required',
      };
    }
  
    if (!adType) {
      return {
        isValid: false,
        reason: 'missing_ad_type',
        message: 'adType is required',
      };
    }
  
    return {
      isValid: true,
    };
  }

  function validateTrackConversionRequest(requestData) {
    const { orderId, productIds } = requestData || {};
  
    if (!orderId) {
      return {
        isValid: false,
        reason: 'missing_order_id',
        message: 'orderId is required',
      };
    }
  
    if (!productIds || !Array.isArray(productIds)) {
      return {
        isValid: false,
        reason: 'invalid_product_ids',
        message: 'productIds array is required',
      };
    }
  
    if (productIds.length === 0) {
      return {
        isValid: false,
        reason: 'empty_product_ids',
        message: 'productIds array cannot be empty',
      };
    }
  
    return {
      isValid: true,
      orderId,
      productCount: productIds.length,
    };
  }

  function validateAnalyticsRequest(requestBody) {
    const { adId, userId } = requestBody || {};
  
    if (!adId) {
      return {
        isValid: false,
        reason: 'missing_ad_id',
        message: 'adId is required',
      };
    }
  
    if (!userId) {
      return {
        isValid: false,
        reason: 'missing_user_id',
        message: 'userId is required',
      };
    }
  
    return {
      isValid: true,
    };
  }
  
  // ============================================================================
  // CONVERSION MATCHING
  // Mirrors: conversion logic in trackAdConversion
  // ============================================================================
 
  function isConversion(clickData, productIds, shopIds) {
    if (!clickData || !clickData.linkedType || !clickData.linkedId) {
      return false;
    }
  
    if (clickData.linkedType === 'product' && productIds.includes(clickData.linkedId)) {
      return true;
    }
  
    if (clickData.linkedType === 'shop' && shopIds && shopIds.includes(clickData.linkedId)) {
      return true;
    }
  
    return false;
  }
  
 
  function getAttributionWindowMs(days = 30) {
    return days * 24 * 60 * 60 * 1000;
  }

  function isWithinAttributionWindow(clickTimestamp, conversionTimestamp, windowDays = 30) {
    const windowMs = getAttributionWindowMs(windowDays);
    return (conversionTimestamp - clickTimestamp) <= windowMs;
  }
  
  // ============================================================================
  // CONVERSION RATE CALCULATION
  // Mirrors: conversion rate in createDailyAdAnalyticsSnapshot
  // ============================================================================
 
  function calculateConversionRate(clicks, conversions) {
    if (!clicks || clicks <= 0) return 0;
    return ((conversions || 0) / clicks) * 100;
  }

  function calculateConversionRatePrecise(clicks, conversions, precision = 2) {
    const rate = calculateConversionRate(clicks, conversions);
    const multiplier = Math.pow(10, precision);
    return Math.round(rate * multiplier) / multiplier;
  }
  
  // ============================================================================
  // DEMOGRAPHICS AGGREGATION
  // Mirrors: demographics structure in processAdAnalytics
  // ============================================================================

  function createEmptyDemographics() {
    return {
      gender: {},
      ageGroups: {},
    };
  }

  function getGenderFieldPath(gender) {
    return `demographics.gender.${gender}`;
  }

  function getAgeGroupFieldPath(ageGroup) {
    return `demographics.ageGroups.${ageGroup}`;
  }

  function mergeDemographics(existing, gender, ageGroup) {
    const result = {
      gender: { ...(existing?.gender || {}) },
      ageGroups: { ...(existing?.ageGroups || {}) },
    };
  
    result.gender[gender] = (result.gender[gender] || 0) + 1;
    result.ageGroups[ageGroup] = (result.ageGroups[ageGroup] || 0) + 1;
  
    return result;
  }
  
  // ============================================================================
  // SNAPSHOT DATE FORMATTING
  // Mirrors: date formatting in createDailyAdAnalyticsSnapshot
  // ============================================================================

  function getSnapshotDate(date = new Date()) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  function getSnapshotDocId(date = new Date()) {
    return date.toISOString().split('T')[0];
  }
  
  // ============================================================================
  // AD COLLECTION NAMES (reuse from ad-payment-utils if available)
  // ============================================================================
  
  /**
   * Ad type to collection name mapping
   */
  const AD_COLLECTION_MAP = {
    topBanner: 'market_top_ads_banners',
    thinBanner: 'market_thin_banners',
    marketBanner: 'market_banners',
  };

  function getAdCollectionName(adType) {
    return AD_COLLECTION_MAP[adType] || 'market_banners';
  }

  function getAllAdCollectionNames() {
    return ['market_top_ads_banners', 'market_thin_banners', 'market_banners'];
  }
  
  // ============================================================================
  // ANALYTICS DATA BUILDER
  // Mirrors: analytics data creation in trackAdClick
  // ============================================================================

  function buildAnalyticsData(params) {
    const {
      adId,
      adType,
      userId,
      gender,
      age,
      ageGroup,
      linkedType,
      linkedId,
      eventType = 'click',
    } = params;
  
    return {
      adId,
      adType,
      userId,
      gender: gender || 'Not specified',
      age: age || null,
      ageGroup: ageGroup || 'Unknown',
      linkedType: linkedType || null,
      linkedId: linkedId || null,
      timestamp: Date.now(),
      eventType,
    };
  }

  function buildClickRecord(params) {
    const {
      userId,
      gender,
      age,
      ageGroup,
      linkedType,
      linkedId,
    } = params;
  
    return {
      userId,
      gender: gender || 'Not specified',
      age: age || null,
      ageGroup: ageGroup || 'Unknown',
      linkedType: linkedType || null,
      linkedId: linkedId || null,
      converted: false,
    };
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Age calculation
    calculateAge,
    calculateAgeFromDate,
  
    // Age groups
    AGE_GROUP_BOUNDARIES,
    getAgeGroup,
    getAllAgeGroups,
    isValidAgeGroup,
  
    // Gender
    VALID_GENDERS,
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
    AD_COLLECTION_MAP,
    getAdCollectionName,
    getAllAdCollectionNames,
  
    // Data builders
    buildAnalyticsData,
    buildClickRecord,
  };

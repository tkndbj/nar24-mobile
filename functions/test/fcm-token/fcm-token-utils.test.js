// functions/test/fcm-token/fcm-token-utils.test.js
//
// Unit tests for FCM token management utility functions
// Tests the EXACT logic from FCM token cloud functions
//
// Run: npx jest test/fcm-token/fcm-token-utils.test.js

const {
    VALID_PLATFORMS,
    MIN_TOKEN_LENGTH,
    MAX_TOKENS_PER_USER,
  
    validateFcmToken,
    isValidFcmToken,
  
    validateDeviceId,
    isValidDeviceId,
  
    validatePlatform,
    isValidPlatform,
    getValidPlatforms,
  
    validateRegisterInput,
    validateRemoveInput,
    validateCleanupInput,
  
    removeTokensByDeviceId,
    removeExactToken,
  
    extractTimestamp,
    sortTokensByRecency,
  
    limitTokenCount,
    shouldLimitTokens,
    getTokenCount,
  
    buildTokenEntry,
  
    cleanupAndAddToken,
    removeTokens,
  
    findTokenByDeviceId,
    tokenExists,
    getDeviceIds,
  
    buildRegisterSuccessResponse,
    buildRemoveSuccessResponse,
    buildCleanupSuccessResponse,
  } = require('./fcm-token-utils');
  
  // ============================================================================
  // HELPER: Generate valid FCM token
  // ============================================================================
  function generateToken(length = 152) {
    return 'fcm_token_' + 'x'.repeat(length - 10);
  }
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('VALID_PLATFORMS contains ios, android, web', () => {
      expect(VALID_PLATFORMS).toContain('ios');
      expect(VALID_PLATFORMS).toContain('android');
      expect(VALID_PLATFORMS).toContain('web');
    });
  
    test('MIN_TOKEN_LENGTH is 50', () => {
      expect(MIN_TOKEN_LENGTH).toBe(50);
    });
  
    test('MAX_TOKENS_PER_USER is 5', () => {
      expect(MAX_TOKENS_PER_USER).toBe(5);
    });
  });
  
  // ============================================================================
  // TOKEN VALIDATION TESTS
  // ============================================================================
  describe('validateFcmToken', () => {
    test('returns invalid for null', () => {
      const result = validateFcmToken(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for undefined', () => {
      const result = validateFcmToken(undefined);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-string', () => {
      const result = validateFcmToken(12345);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns invalid for short token', () => {
      const result = validateFcmToken('short_token');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('too_short');
    });
  
    test('returns valid for token >= 50 chars', () => {
      const token = generateToken(50);
      expect(validateFcmToken(token).isValid).toBe(true);
    });
  
    test('returns valid for long token', () => {
      const token = generateToken(200);
      expect(validateFcmToken(token).isValid).toBe(true);
    });
  });
  
  describe('isValidFcmToken', () => {
    test('returns true for valid token', () => {
      expect(isValidFcmToken(generateToken())).toBe(true);
    });
  
    test('returns false for invalid token', () => {
      expect(isValidFcmToken('short')).toBe(false);
    });
  });
  
  // ============================================================================
  // DEVICE ID VALIDATION TESTS
  // ============================================================================
  describe('validateDeviceId', () => {
    test('returns invalid for null', () => {
      const result = validateDeviceId(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for non-string', () => {
      const result = validateDeviceId(12345);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns valid for string device ID', () => {
      expect(validateDeviceId('device-123').isValid).toBe(true);
    });
  });
  
  describe('isValidDeviceId', () => {
    test('returns true for valid device ID', () => {
      expect(isValidDeviceId('device-123')).toBe(true);
    });
  
    test('returns false for invalid device ID', () => {
      expect(isValidDeviceId(null)).toBe(false);
    });
  });
  
  // ============================================================================
  // PLATFORM VALIDATION TESTS
  // ============================================================================
  describe('validatePlatform', () => {
    test('returns invalid for null', () => {
      const result = validatePlatform(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for unknown platform', () => {
      const result = validatePlatform('windows');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_value');
    });
  
    test('returns valid for ios', () => {
      expect(validatePlatform('ios').isValid).toBe(true);
    });
  
    test('returns valid for android', () => {
      expect(validatePlatform('android').isValid).toBe(true);
    });
  
    test('returns valid for web', () => {
      expect(validatePlatform('web').isValid).toBe(true);
    });
  });
  
  describe('isValidPlatform', () => {
    test('returns true for valid platform', () => {
      expect(isValidPlatform('ios')).toBe(true);
    });
  
    test('returns false for invalid platform', () => {
      expect(isValidPlatform('macos')).toBe(false);
    });
  });
  
  describe('getValidPlatforms', () => {
    test('returns all valid platforms', () => {
      expect(getValidPlatforms()).toEqual(['ios', 'android', 'web']);
    });
  });
  
  // ============================================================================
  // COMPLETE INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateRegisterInput', () => {
    test('returns valid for complete input', () => {
      const data = {
        token: generateToken(),
        deviceId: 'device-123',
        platform: 'ios',
      };
      expect(validateRegisterInput(data).isValid).toBe(true);
    });
  
    test('returns invalid for missing token', () => {
      const data = { deviceId: 'device-123', platform: 'ios' };
      const result = validateRegisterInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'token')).toBe(true);
    });
  
    test('returns invalid for missing deviceId', () => {
      const data = { token: generateToken(), platform: 'ios' };
      const result = validateRegisterInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'deviceId')).toBe(true);
    });
  
    test('returns invalid for missing platform', () => {
      const data = { token: generateToken(), deviceId: 'device-123' };
      const result = validateRegisterInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'platform')).toBe(true);
    });
  
    test('returns multiple errors', () => {
      const result = validateRegisterInput({});
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBe(3);
    });
  });
  
  describe('validateRemoveInput', () => {
    test('returns valid for token only', () => {
      expect(validateRemoveInput({ token: generateToken() }).isValid).toBe(true);
    });
  
    test('returns valid for deviceId only', () => {
      expect(validateRemoveInput({ deviceId: 'device-123' }).isValid).toBe(true);
    });
  
    test('returns invalid for neither', () => {
      const result = validateRemoveInput({});
      expect(result.isValid).toBe(false);
      expect(result.message).toBe('Token or device ID required');
    });
  });
  
  describe('validateCleanupInput', () => {
    test('returns valid for complete input', () => {
      const data = { userId: 'user-123', invalidToken: generateToken() };
      expect(validateCleanupInput(data).isValid).toBe(true);
    });
  
    test('returns invalid for missing userId', () => {
      const data = { invalidToken: generateToken() };
      const result = validateCleanupInput(data);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for missing invalidToken', () => {
      const data = { userId: 'user-123' };
      const result = validateCleanupInput(data);
      expect(result.isValid).toBe(false);
    });
  });
  
  // ============================================================================
  // TOKEN REMOVAL BY DEVICE ID TESTS
  // ============================================================================
  describe('removeTokensByDeviceId', () => {
    test('removes tokens matching deviceId', () => {
      const tokens = {
        token1: { deviceId: 'device-A', platform: 'ios' },
        token2: { deviceId: 'device-B', platform: 'android' },
        token3: { deviceId: 'device-A', platform: 'ios' },
      };
      const result = removeTokensByDeviceId(tokens, 'device-A');
      expect(Object.keys(result.tokens)).toEqual(['token2']);
      expect(result.removedCount).toBe(2);
    });
  
    test('returns all tokens if no match', () => {
      const tokens = {
        token1: { deviceId: 'device-A', platform: 'ios' },
      };
      const result = removeTokensByDeviceId(tokens, 'device-B');
      expect(Object.keys(result.tokens)).toEqual(['token1']);
      expect(result.removedCount).toBe(0);
    });
  
    test('handles null tokens', () => {
      expect(removeTokensByDeviceId(null, 'device-A')).toEqual({});
    });
  
    test('handles null deviceId', () => {
      const tokens = { token1: { deviceId: 'device-A' } };
      const result = removeTokensByDeviceId(tokens, null);
      expect(result.token1).toBeDefined();
    });
  });
  
  // ============================================================================
  // TOKEN REMOVAL BY EXACT TOKEN TESTS
  // ============================================================================
  describe('removeExactToken', () => {
    test('removes exact token', () => {
      const tokens = {
        token1: { deviceId: 'device-A' },
        token2: { deviceId: 'device-B' },
      };
      const result = removeExactToken(tokens, 'token1');
      expect(result.tokens.token1).toBeUndefined();
      expect(result.tokens.token2).toBeDefined();
      expect(result.removed).toBe(true);
    });
  
    test('returns removed=false if not found', () => {
      const tokens = { token1: { deviceId: 'device-A' } };
      const result = removeExactToken(tokens, 'nonexistent');
      expect(result.removed).toBe(false);
      expect(Object.keys(result.tokens)).toEqual(['token1']);
    });
  
    test('handles null tokens', () => {
      const result = removeExactToken(null, 'token1');
      expect(result.tokens).toEqual({});
      expect(result.removed).toBe(false);
    });
  });
  
  // ============================================================================
  // TIMESTAMP EXTRACTION TESTS
  // ============================================================================
  describe('extractTimestamp', () => {
    test('extracts from Date lastSeen', () => {
      const data = { lastSeen: new Date('2024-06-15') };
      expect(extractTimestamp(data)).toBe(new Date('2024-06-15').getTime());
    });
  
    test('extracts from Firestore timestamp', () => {
      const data = { lastSeen: { toDate: () => new Date('2024-06-15') } };
      expect(extractTimestamp(data)).toBe(new Date('2024-06-15').getTime());
    });
  
    test('falls back to registeredAt', () => {
      const data = { registeredAt: new Date('2024-01-01') };
      expect(extractTimestamp(data)).toBe(new Date('2024-01-01').getTime());
    });
  
    test('returns 0 for null', () => {
      expect(extractTimestamp(null)).toBe(0);
    });
  
    test('returns 0 for no timestamps', () => {
      expect(extractTimestamp({ deviceId: 'test' })).toBe(0);
    });
  });
  
  // ============================================================================
  // SORTING TESTS
  // ============================================================================
  describe('sortTokensByRecency', () => {
    test('sorts most recent first', () => {
      const tokens = {
        old: { lastSeen: new Date('2024-01-01') },
        new: { lastSeen: new Date('2024-06-01') },
        mid: { lastSeen: new Date('2024-03-01') },
      };
      const sorted = sortTokensByRecency(tokens);
      expect(sorted[0][0]).toBe('new');
      expect(sorted[1][0]).toBe('mid');
      expect(sorted[2][0]).toBe('old');
    });
  
    test('handles null', () => {
      expect(sortTokensByRecency(null)).toEqual([]);
    });
  
    test('handles empty object', () => {
      expect(sortTokensByRecency({})).toEqual([]);
    });
  });
  
  // ============================================================================
  // TOKEN LIMITING TESTS
  // ============================================================================
  describe('limitTokenCount', () => {
    test('limits to specified count', () => {
      const tokens = {
        t1: { lastSeen: new Date('2024-01-01') },
        t2: { lastSeen: new Date('2024-02-01') },
        t3: { lastSeen: new Date('2024-03-01') },
        t4: { lastSeen: new Date('2024-04-01') },
        t5: { lastSeen: new Date('2024-05-01') },
      };
      const limited = limitTokenCount(tokens, 3);
      expect(Object.keys(limited).length).toBe(3);
      // Should keep most recent
      expect(limited.t5).toBeDefined();
      expect(limited.t4).toBeDefined();
      expect(limited.t3).toBeDefined();
    });
  
    test('returns all if under limit', () => {
      const tokens = { t1: {}, t2: {} };
      const limited = limitTokenCount(tokens, 5);
      expect(Object.keys(limited).length).toBe(2);
    });
  
    test('handles null', () => {
      expect(limitTokenCount(null, 3)).toEqual({});
    });
  });
  
  describe('shouldLimitTokens', () => {
    test('returns true at limit', () => {
      const tokens = { t1: {}, t2: {}, t3: {}, t4: {}, t5: {} };
      expect(shouldLimitTokens(tokens, 5)).toBe(true);
    });
  
    test('returns false under limit', () => {
      const tokens = { t1: {}, t2: {} };
      expect(shouldLimitTokens(tokens, 5)).toBe(false);
    });
  });
  
  describe('getTokenCount', () => {
    test('counts tokens', () => {
      const tokens = { t1: {}, t2: {}, t3: {} };
      expect(getTokenCount(tokens)).toBe(3);
    });
  
    test('returns 0 for null', () => {
      expect(getTokenCount(null)).toBe(0);
    });
  });
  
  // ============================================================================
  // TOKEN ENTRY BUILDING TESTS
  // ============================================================================
  describe('buildTokenEntry', () => {
    test('builds token entry', () => {
      const entry = buildTokenEntry('device-123', 'ios');
      expect(entry.deviceId).toBe('device-123');
      expect(entry.platform).toBe('ios');
    });
  });
  
  // ============================================================================
  // COMBINED CLEANUP TESTS
  // ============================================================================
  describe('cleanupAndAddToken', () => {
    test('removes existing device tokens and adds new', () => {
      const existingTokens = {
        oldToken: { deviceId: 'device-A', platform: 'ios' },
      };
      const newToken = generateToken();
      const result = cleanupAndAddToken(existingTokens, newToken, 'device-A', 'android');
      
      expect(result.oldToken).toBeUndefined();
      expect(result[newToken]).toBeDefined();
      expect(result[newToken].platform).toBe('android');
    });
  
    test('removes duplicate token under different device', () => {
      const token = generateToken();
      const existingTokens = {
        [token]: { deviceId: 'device-B', platform: 'ios' },
      };
      const result = cleanupAndAddToken(existingTokens, token, 'device-A', 'android');
      
      expect(Object.keys(result).length).toBe(1);
      expect(result[token].deviceId).toBe('device-A');
    });
  
    test('limits total tokens to 5', () => {
      const existingTokens = {};
      for (let i = 1; i <= 6; i++) {
        existingTokens[`token${i}`] = { 
          deviceId: `device-${i}`, 
          lastSeen: new Date(2024, 0, i) 
        };
      }
      const newToken = generateToken();
      const result = cleanupAndAddToken(existingTokens, newToken, 'new-device', 'ios');
      
      expect(Object.keys(result).length).toBeLessThanOrEqual(5);
      expect(result[newToken]).toBeDefined();
    });
  
    test('handles null existing tokens', () => {
      const newToken = generateToken();
      const result = cleanupAndAddToken(null, newToken, 'device-A', 'ios');
      expect(result[newToken]).toBeDefined();
    });
  });
  
  // ============================================================================
  // COMBINED REMOVAL TESTS
  // ============================================================================
  describe('removeTokens', () => {
    test('removes by token', () => {
      const tokens = { token1: {}, token2: {} };
      const result = removeTokens(tokens, 'token1', null);
      expect(result.tokens.token1).toBeUndefined();
      expect(result.removedCount).toBe(1);
    });
  
    test('removes by deviceId', () => {
      const tokens = {
        token1: { deviceId: 'device-A' },
        token2: { deviceId: 'device-B' },
      };
      const result = removeTokens(tokens, null, 'device-A');
      expect(result.tokens.token1).toBeUndefined();
      expect(result.removedCount).toBe(1);
    });
  
    test('removes by both', () => {
      const tokens = {
        token1: { deviceId: 'device-A' },
        token2: { deviceId: 'device-A' },
        token3: { deviceId: 'device-B' },
      };
      const result = removeTokens(tokens, 'token3', 'device-A');
      expect(Object.keys(result.tokens).length).toBe(0);
      expect(result.removedCount).toBe(3);
    });
  });
  
  // ============================================================================
  // TOKEN LOOKUP TESTS
  // ============================================================================
  describe('findTokenByDeviceId', () => {
    test('finds token by device ID', () => {
      const tokens = {
        token1: { deviceId: 'device-A' },
        token2: { deviceId: 'device-B' },
      };
      const result = findTokenByDeviceId(tokens, 'device-A');
      expect(result.token).toBe('token1');
    });
  
    test('returns null if not found', () => {
      const tokens = { token1: { deviceId: 'device-A' } };
      expect(findTokenByDeviceId(tokens, 'device-B')).toBe(null);
    });
  });
  
  describe('tokenExists', () => {
    test('returns true if exists', () => {
      const tokens = { token1: {} };
      expect(tokenExists(tokens, 'token1')).toBe(true);
    });
  
    test('returns false if not exists', () => {
      const tokens = { token1: {} };
      expect(tokenExists(tokens, 'token2')).toBe(false);
    });
  });
  
  describe('getDeviceIds', () => {
    test('extracts device IDs', () => {
      const tokens = {
        t1: { deviceId: 'device-A' },
        t2: { deviceId: 'device-B' },
      };
      expect(getDeviceIds(tokens)).toEqual(['device-A', 'device-B']);
    });
  
    test('filters null device IDs', () => {
      const tokens = {
        t1: { deviceId: 'device-A' },
        t2: { platform: 'ios' },
      };
      expect(getDeviceIds(tokens)).toEqual(['device-A']);
    });
  });
  
  // ============================================================================
  // RESPONSE BUILDING TESTS
  // ============================================================================
  describe('buildRegisterSuccessResponse', () => {
    test('builds response with deviceId', () => {
      const response = buildRegisterSuccessResponse('device-123');
      expect(response.success).toBe(true);
      expect(response.deviceId).toBe('device-123');
    });
  });
  
  describe('buildRemoveSuccessResponse', () => {
    test('builds remove success response', () => {
      const response = buildRemoveSuccessResponse();
      expect(response.success).toBe(true);
      expect(response.removed).toBe(true);
    });
  });
  
  describe('buildCleanupSuccessResponse', () => {
    test('builds cleanup success response', () => {
      const response = buildCleanupSuccessResponse();
      expect(response.success).toBe(true);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete token registration flow', () => {
      const input = {
        token: generateToken(),
        deviceId: 'iphone-uuid-123',
        platform: 'ios',
      };
  
      // Validate input
      const validation = validateRegisterInput(input);
      expect(validation.isValid).toBe(true);
  
      // Simulate existing tokens
      const existingTokens = {
        oldToken: { deviceId: 'iphone-uuid-123', platform: 'ios', lastSeen: new Date('2024-01-01') },
      };
  
      // Cleanup and add
      const newTokens = cleanupAndAddToken(
        existingTokens,
        input.token,
        input.deviceId,
        input.platform
      );
  
      // Old token should be removed (same device)
      expect(newTokens.oldToken).toBeUndefined();
      // New token should exist
      expect(newTokens[input.token]).toBeDefined();
      expect(newTokens[input.token].deviceId).toBe('iphone-uuid-123');
  
      // Build response
      const response = buildRegisterSuccessResponse(input.deviceId);
      expect(response.success).toBe(true);
    });
  
    test('logout flow - remove token', () => {
      const existingTokens = {
        token1: { deviceId: 'device-A' },
        token2: { deviceId: 'device-B' },
      };
  
      // Validate remove input
      const input = { deviceId: 'device-A' };
      expect(validateRemoveInput(input).isValid).toBe(true);
  
      // Remove tokens
      const result = removeTokens(existingTokens, null, 'device-A');
      expect(result.tokens.token1).toBeUndefined();
      expect(result.tokens.token2).toBeDefined();
    });
  
    test('max tokens enforcement', () => {
      // User has 5 tokens on different devices
      const existingTokens = {};
      for (let i = 1; i <= 5; i++) {
        existingTokens[`token${i}`] = {
          deviceId: `device-${i}`,
          lastSeen: new Date(2024, 0, i), // Older dates for lower numbers
        };
      }
  
      // New device registers
      const newToken = generateToken();
      const result = cleanupAndAddToken(existingTokens, newToken, 'device-new', 'ios');
  
      // Should have at most 5 tokens
      expect(Object.keys(result).length).toBeLessThanOrEqual(5);
      // New token should be present
      expect(result[newToken]).toBeDefined();
      // Oldest token should be removed
      expect(result.token1).toBeUndefined();
    });
  });

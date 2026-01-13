// functions/test/fcm-token/fcm-token-utils.js
//
// EXTRACTED PURE LOGIC from FCM token management cloud functions
// These functions are EXACT COPIES of logic from the FCM functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source FCM functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const VALID_PLATFORMS = ['ios', 'android', 'web'];
const MIN_TOKEN_LENGTH = 50;
const MAX_TOKENS_PER_USER = 5;

// ============================================================================
// TOKEN VALIDATION
// ============================================================================

function validateFcmToken(token) {
  if (!token) {
    return { isValid: false, reason: 'missing', message: 'Invalid FCM token' };
  }

  if (typeof token !== 'string') {
    return { isValid: false, reason: 'not_string', message: 'Invalid FCM token' };
  }

  if (token.length < MIN_TOKEN_LENGTH) {
    return { isValid: false, reason: 'too_short', message: 'Invalid FCM token' };
  }

  return { isValid: true };
}

function isValidFcmToken(token) {
  return validateFcmToken(token).isValid;
}

// ============================================================================
// DEVICE ID VALIDATION
// ============================================================================

function validateDeviceId(deviceId) {
  if (!deviceId) {
    return { isValid: false, reason: 'missing', message: 'Device ID required' };
  }

  if (typeof deviceId !== 'string') {
    return { isValid: false, reason: 'not_string', message: 'Device ID required' };
  }

  return { isValid: true };
}

function isValidDeviceId(deviceId) {
  return validateDeviceId(deviceId).isValid;
}

// ============================================================================
// PLATFORM VALIDATION
// ============================================================================

function validatePlatform(platform) {
  if (!platform) {
    return { isValid: false, reason: 'missing', message: 'Invalid platform' };
  }

  if (!VALID_PLATFORMS.includes(platform)) {
    return { isValid: false, reason: 'invalid_value', message: 'Invalid platform' };
  }

  return { isValid: true };
}

function isValidPlatform(platform) {
  return validatePlatform(platform).isValid;
}

function getValidPlatforms() {
  return VALID_PLATFORMS;
}

// ============================================================================
// COMPLETE INPUT VALIDATION
// ============================================================================

function validateRegisterInput(data) {
  const errors = [];

  const tokenResult = validateFcmToken(data.token);
  if (!tokenResult.isValid) {
    errors.push({ field: 'token', ...tokenResult });
  }

  const deviceIdResult = validateDeviceId(data.deviceId);
  if (!deviceIdResult.isValid) {
    errors.push({ field: 'deviceId', ...deviceIdResult });
  }

  const platformResult = validatePlatform(data.platform);
  if (!platformResult.isValid) {
    errors.push({ field: 'platform', ...platformResult });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, firstError: errors[0] };
  }

  return { isValid: true };
}

function validateRemoveInput(data) {
  if (!data.token && !data.deviceId) {
    return { 
      isValid: false, 
      message: 'Token or device ID required' 
    };
  }

  return { isValid: true };
}

function validateCleanupInput(data) {
  const errors = [];

  if (!data.userId) {
    errors.push({ field: 'userId', message: 'Missing required parameters' });
  }

  if (!data.invalidToken) {
    errors.push({ field: 'invalidToken', message: 'Missing required parameters' });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, message: 'Missing required parameters' };
  }

  return { isValid: true };
}

// ============================================================================
// TOKEN REMOVAL BY DEVICE ID
// ============================================================================

function removeTokensByDeviceId(fcmTokens, deviceId) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return {};
  if (!deviceId) return { ...fcmTokens };

  const result = {};
  let removedCount = 0;

  Object.keys(fcmTokens).forEach((token) => {
    if (fcmTokens[token]?.deviceId !== deviceId) {
      result[token] = fcmTokens[token];
    } else {
      removedCount++;
    }
  });

  return { tokens: result, removedCount };
}

// ============================================================================
// TOKEN REMOVAL BY EXACT TOKEN
// ============================================================================

function removeExactToken(fcmTokens, token) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return { tokens: {}, removed: false };
  if (!token) return { tokens: { ...fcmTokens }, removed: false };

  const result = { ...fcmTokens };
  const existed = token in result;
  
  if (existed) {
    delete result[token];
  }

  return { tokens: result, removed: existed };
}

// ============================================================================
// TOKEN SORTING BY RECENCY
// ============================================================================

function extractTimestamp(tokenData) {
  if (!tokenData) return 0;
  
  // Try lastSeen first, then registeredAt
  const lastSeen = tokenData.lastSeen;
  const registeredAt = tokenData.registeredAt;

  if (lastSeen?.toDate) {
    return lastSeen.toDate().getTime();
  }
  if (lastSeen instanceof Date) {
    return lastSeen.getTime();
  }
  if (typeof lastSeen === 'number') {
    return lastSeen;
  }

  if (registeredAt?.toDate) {
    return registeredAt.toDate().getTime();
  }
  if (registeredAt instanceof Date) {
    return registeredAt.getTime();
  }
  if (typeof registeredAt === 'number') {
    return registeredAt;
  }

  return 0;
}

function sortTokensByRecency(fcmTokens) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return [];

  const entries = Object.entries(fcmTokens);
  
  return entries.sort((a, b) => {
    const aTime = extractTimestamp(a[1]);
    const bTime = extractTimestamp(b[1]);
    return bTime - aTime; // Most recent first
  });
}

// ============================================================================
// TOKEN LIMITING
// ============================================================================

function limitTokenCount(fcmTokens, maxCount = MAX_TOKENS_PER_USER - 1) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return {};

  const sortedEntries = sortTokensByRecency(fcmTokens);
  
  if (sortedEntries.length <= maxCount) {
    return fcmTokens;
  }

  // Keep only the most recent tokens
  const keptEntries = sortedEntries.slice(0, maxCount);
  return Object.fromEntries(keptEntries);
}

function shouldLimitTokens(fcmTokens, maxCount = MAX_TOKENS_PER_USER) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return false;
  return Object.keys(fcmTokens).length >= maxCount;
}

function getTokenCount(fcmTokens) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return 0;
  return Object.keys(fcmTokens).length;
}

// ============================================================================
// TOKEN ENTRY BUILDING
// ============================================================================

function buildTokenEntry(deviceId, platform) {
  return {
    deviceId,
    platform,
    // Note: registeredAt and lastSeen are set with serverTimestamp in actual code
  };
}

// ============================================================================
// COMBINED TOKEN CLEANUP
// ============================================================================

function cleanupAndAddToken(fcmTokens, newToken, deviceId, platform) {
  let tokens = { ...(fcmTokens || {}) };

  // Step 1: Remove any existing tokens for this device
  const afterDeviceRemoval = removeTokensByDeviceId(tokens, deviceId);
  tokens = afterDeviceRemoval.tokens;

  // Step 2: Also remove if this exact token exists under different device
  const afterExactRemoval = removeExactToken(tokens, newToken);
  tokens = afterExactRemoval.tokens;

  // Step 3: Limit to 4 tokens (leaving room for new one)
  if (Object.keys(tokens).length >= MAX_TOKENS_PER_USER) {
    tokens = limitTokenCount(tokens, MAX_TOKENS_PER_USER - 1);
  }

  // Step 4: Add new token
  tokens[newToken] = buildTokenEntry(deviceId, platform);

  return tokens;
}

// ============================================================================
// TOKEN REMOVAL COMBINED
// ============================================================================

function removeTokens(fcmTokens, token, deviceId) {
  let tokens = { ...(fcmTokens || {}) };
  let removedCount = 0;

  if (token) {
    const result = removeExactToken(tokens, token);
    tokens = result.tokens;
    if (result.removed) removedCount++;
  }

  if (deviceId) {
    const result = removeTokensByDeviceId(tokens, deviceId);
    tokens = result.tokens;
    removedCount += result.removedCount;
  }

  return { tokens, removedCount };
}

// ============================================================================
// TOKEN LOOKUP
// ============================================================================

function findTokenByDeviceId(fcmTokens, deviceId) {
  if (!fcmTokens || !deviceId) return null;

  for (const [token, data] of Object.entries(fcmTokens)) {
    if (data?.deviceId === deviceId) {
      return { token, data };
    }
  }

  return null;
}

function tokenExists(fcmTokens, token) {
  if (!fcmTokens || !token) return false;
  return token in fcmTokens;
}

function getDeviceIds(fcmTokens) {
  if (!fcmTokens || typeof fcmTokens !== 'object') return [];
  return Object.values(fcmTokens)
    .map((data) => data?.deviceId)
    .filter(Boolean);
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildRegisterSuccessResponse(deviceId) {
  return { success: true, deviceId };
}

function buildRemoveSuccessResponse() {
  return { success: true, removed: true };
}

function buildCleanupSuccessResponse() {
  return { success: true };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  VALID_PLATFORMS,
  MIN_TOKEN_LENGTH,
  MAX_TOKENS_PER_USER,

  // Token validation
  validateFcmToken,
  isValidFcmToken,

  // Device ID validation
  validateDeviceId,
  isValidDeviceId,

  // Platform validation
  validatePlatform,
  isValidPlatform,
  getValidPlatforms,

  // Complete input validation
  validateRegisterInput,
  validateRemoveInput,
  validateCleanupInput,

  // Token removal
  removeTokensByDeviceId,
  removeExactToken,

  // Token sorting
  extractTimestamp,
  sortTokensByRecency,

  // Token limiting
  limitTokenCount,
  shouldLimitTokens,
  getTokenCount,

  // Token entry
  buildTokenEntry,

  // Combined operations
  cleanupAndAddToken,
  removeTokens,

  // Token lookup
  findTokenByDeviceId,
  tokenExists,
  getDeviceIds,

  // Response building
  buildRegisterSuccessResponse,
  buildRemoveSuccessResponse,
  buildCleanupSuccessResponse,
};

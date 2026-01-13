// functions/test/2fa/2fa-utils.test.js
//
// Unit tests for 2FA (Two-Factor Authentication) utility functions
// Tests the EXACT logic from 2FA cloud functions
//
// Run: npx jest test/2fa/2fa-utils.test.js

const {
    CODE_LENGTH,

    TOTP_STEP_SECONDS,
    VALID_ACTIONS,

    MAX_ATTEMPTS,
    THROTTLE_WINDOW_MS,

    LOGIN_CODE_TTL_MINUTES,
    SETUP_CODE_TTL_MINUTES,
    RECENT_2FA_VALIDITY_MS,
    ISSUER,
  
    sanitizeCode,
    validateCode,
    isValidCode,
  
    validateAction,
    getValidAction,
    isValidAction,
  
    isCodeExpired,
    calculateCodeExpiry,
    getCodeTtlMinutes,
  
    hasExceededAttempts,
    calculateRemainingAttempts,
    shouldDeleteCodeAfterAttempt,
    incrementAttempts,
  
    isWithinThrottleWindow,
    getThrottleRemainingSeconds,
  
    isWithinTotpRateLimitWindow,

    isTotpRateLimited,
  
    isRecent2FAValid,

  
    buildVerificationSuccessResult,
    buildVerificationFailureResult,
    buildCodeNotFoundResult,

    buildInvalidCodeResult,
    buildThrottledResult,
    buildEmailSentResult,
  

    buildTotpSecretResult,
    buildTotpEnabledResult,

    getUserUpdateForAction,
  
    buildTotpConfigPending,
    buildTotpConfigEnabled,
  
    buildVerificationCodeDocument,
  
    getVerificationCodesPath,
    getTotpAttemptsPath,
    getUserSecretsPath,
  
    buildOtpAuthUri,
    parseOtpAuthUri,
  
    isExpiredCode,
    isStaleAttempt,
  
    getEmailTemplate,
    getEmailSubject,
  } = require('./2fa-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('CODE_LENGTH is 6', () => {
      expect(CODE_LENGTH).toBe(6);
    });
  
    test('TOTP_STEP_SECONDS is 30', () => {
      expect(TOTP_STEP_SECONDS).toBe(30);
    });
  
    test('VALID_ACTIONS contains login, setup, disable', () => {
      expect(VALID_ACTIONS).toContain('login');
      expect(VALID_ACTIONS).toContain('setup');
      expect(VALID_ACTIONS).toContain('disable');
    });
  
    test('MAX_ATTEMPTS is 5', () => {
      expect(MAX_ATTEMPTS).toBe(5);
    });
  
    test('THROTTLE_WINDOW_MS is 30 seconds', () => {
      expect(THROTTLE_WINDOW_MS).toBe(30000);
    });
  
    test('LOGIN_CODE_TTL_MINUTES is 5', () => {
      expect(LOGIN_CODE_TTL_MINUTES).toBe(5);
    });
  
    test('SETUP_CODE_TTL_MINUTES is 10', () => {
      expect(SETUP_CODE_TTL_MINUTES).toBe(10);
    });
  
    test('ISSUER is Nar24', () => {
      expect(ISSUER).toBe('Nar24');
    });
  });
  
  // ============================================================================
  // CODE VALIDATION TESTS
  // ============================================================================
  describe('sanitizeCode', () => {
    test('removes non-digits', () => {
      expect(sanitizeCode('12-34-56')).toBe('123456');
      expect(sanitizeCode('abc123def456')).toBe('123456');
    });
  
    test('handles null', () => {
      expect(sanitizeCode(null)).toBe('');
    });
  
    test('converts number to string', () => {
      expect(sanitizeCode(123456)).toBe('123456');
    });
  });
  
  describe('validateCode', () => {
    test('returns valid for 6-digit code', () => {
      const result = validateCode('123456');
      expect(result.isValid).toBe(true);
      expect(result.sanitizedCode).toBe('123456');
    });
  
    test('returns invalid for null', () => {
      const result = validateCode(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for wrong length', () => {
      expect(validateCode('12345').isValid).toBe(false);
      expect(validateCode('1234567').isValid).toBe(false);
    });
  
    test('sanitizes and validates', () => {
      const result = validateCode('12-34-56');
      expect(result.isValid).toBe(true);
      expect(result.sanitizedCode).toBe('123456');
    });
  });
  
  describe('isValidCode', () => {
    test('returns true for valid', () => {
      expect(isValidCode('123456')).toBe(true);
    });
  
    test('returns false for invalid', () => {
      expect(isValidCode('12345')).toBe(false);
    });
  });
  
  // ============================================================================
  // ACTION VALIDATION TESTS
  // ============================================================================
  describe('validateAction', () => {
    test('returns login as default for null', () => {
      const result = validateAction(null);
      expect(result.action).toBe('login');
    });
  
    test('returns login for invalid action', () => {
      const result = validateAction('invalid');
      expect(result.action).toBe('login');
    });
  
    test('returns action for valid actions', () => {
      expect(validateAction('login').action).toBe('login');
      expect(validateAction('setup').action).toBe('setup');
      expect(validateAction('disable').action).toBe('disable');
    });
  });
  
  describe('getValidAction', () => {
    test('returns valid actions', () => {
      expect(getValidAction('setup')).toBe('setup');
    });
  
    test('returns default for invalid', () => {
      expect(getValidAction('invalid')).toBe('login');
    });
  });
  
  describe('isValidAction', () => {
    test('returns true for valid', () => {
      expect(isValidAction('login')).toBe(true);
      expect(isValidAction('setup')).toBe(true);
    });
  
    test('returns false for invalid', () => {
      expect(isValidAction('invalid')).toBe(false);
    });
  });
  
  // ============================================================================
  // CODE EXPIRATION TESTS
  // ============================================================================
  describe('isCodeExpired', () => {
    const now = Date.now();
  
    test('returns true for past expiry', () => {
      const pastExpiry = { toMillis: () => now - 60000 };
      expect(isCodeExpired(pastExpiry, now)).toBe(true);
    });
  
    test('returns false for future expiry', () => {
      const futureExpiry = { toMillis: () => now + 60000 };
      expect(isCodeExpired(futureExpiry, now)).toBe(false);
    });
  
    test('returns true for null', () => {
      expect(isCodeExpired(null)).toBe(true);
    });
  
    test('handles Date object', () => {
      const futureDate = new Date(now + 60000);
      expect(isCodeExpired(futureDate, now)).toBe(false);
    });
  });
  
  describe('calculateCodeExpiry', () => {
    test('returns 5 minutes for login', () => {
      const now = Date.now();
      const expiry = calculateCodeExpiry('login', now);
      expect(expiry.getTime() - now).toBe(5 * 60 * 1000);
    });
  
    test('returns 10 minutes for setup', () => {
      const now = Date.now();
      const expiry = calculateCodeExpiry('setup', now);
      expect(expiry.getTime() - now).toBe(10 * 60 * 1000);
    });
  });
  
  describe('getCodeTtlMinutes', () => {
    test('returns 5 for login', () => {
      expect(getCodeTtlMinutes('login')).toBe(5);
    });
  
    test('returns 10 for setup', () => {
      expect(getCodeTtlMinutes('setup')).toBe(10);
    });
  });
  
  // ============================================================================
  // ATTEMPT TRACKING TESTS
  // ============================================================================
  describe('hasExceededAttempts', () => {
    test('returns false for under limit', () => {
      expect(hasExceededAttempts(4, 5)).toBe(false);
    });
  
    test('returns true for at limit', () => {
      expect(hasExceededAttempts(5, 5)).toBe(true);
    });
  
    test('returns true for over limit', () => {
      expect(hasExceededAttempts(6, 5)).toBe(true);
    });
  
    test('handles null as 0', () => {
      expect(hasExceededAttempts(null, 5)).toBe(false);
    });
  });
  
  describe('calculateRemainingAttempts', () => {
    test('calculates remaining', () => {
      expect(calculateRemainingAttempts(3, 5)).toBe(2);
    });
  
    test('returns 0 for exceeded', () => {
      expect(calculateRemainingAttempts(5, 5)).toBe(0);
      expect(calculateRemainingAttempts(6, 5)).toBe(0);
    });
  
    test('handles null', () => {
      expect(calculateRemainingAttempts(null, 5)).toBe(5);
    });
  });
  
  describe('shouldDeleteCodeAfterAttempt', () => {
    test('returns true when will reach max', () => {
      expect(shouldDeleteCodeAfterAttempt(4, 5)).toBe(true);
    });
  
    test('returns false when still under', () => {
      expect(shouldDeleteCodeAfterAttempt(3, 5)).toBe(false);
    });
  });
  
  describe('incrementAttempts', () => {
    test('increments', () => {
      expect(incrementAttempts(3)).toBe(4);
    });
  
    test('handles null', () => {
      expect(incrementAttempts(null)).toBe(1);
    });
  });
  
  // ============================================================================
  // THROTTLING TESTS
  // ============================================================================
  describe('isWithinThrottleWindow', () => {
    const now = Date.now();
  
    test('returns true within window', () => {
      const recent = new Date(now - 10000); // 10 sec ago
      expect(isWithinThrottleWindow(recent, 30000, now)).toBe(true);
    });
  
    test('returns false outside window', () => {
      const old = new Date(now - 40000); // 40 sec ago
      expect(isWithinThrottleWindow(old, 30000, now)).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isWithinThrottleWindow(null, 30000, now)).toBe(false);
    });
  });
  
  describe('getThrottleRemainingSeconds', () => {
    const now = Date.now();
  
    test('calculates remaining seconds', () => {
      const recent = new Date(now - 10000); // 10 sec ago
      const remaining = getThrottleRemainingSeconds(recent, 30000, now);
      expect(remaining).toBe(20); // 30 - 10 = 20
    });
  
    test('returns 0 when expired', () => {
      const old = new Date(now - 40000);
      expect(getThrottleRemainingSeconds(old, 30000, now)).toBe(0);
    });
  });
  
  // ============================================================================
  // TOTP RATE LIMITING TESTS
  // ============================================================================
  describe('isWithinTotpRateLimitWindow', () => {
    const now = Date.now();
  
    test('returns true within 15 min window', () => {
      const recent = new Date(now - 5 * 60 * 1000); // 5 min ago
      expect(isWithinTotpRateLimitWindow(recent, now)).toBe(true);
    });
  
    test('returns false outside window', () => {
      const old = new Date(now - 20 * 60 * 1000); // 20 min ago
      expect(isWithinTotpRateLimitWindow(old, now)).toBe(false);
    });
  });
  
  describe('isTotpRateLimited', () => {
    const now = Date.now();
  
    test('returns true when at limit within window', () => {
      const recent = new Date(now - 5 * 60 * 1000);
      expect(isTotpRateLimited(5, recent, now)).toBe(true);
    });
  
    test('returns false when under limit', () => {
      const recent = new Date(now - 5 * 60 * 1000);
      expect(isTotpRateLimited(4, recent, now)).toBe(false);
    });
  
    test('returns false when outside window', () => {
      const old = new Date(now - 20 * 60 * 1000);
      expect(isTotpRateLimited(5, old, now)).toBe(false);
    });
  });
  
  // ============================================================================
  // RECENT 2FA TESTS
  // ============================================================================
  describe('isRecent2FAValid', () => {
    const now = Date.now();
  
    test('returns true within 5 min', () => {
      const recent = new Date(now - 2 * 60 * 1000); // 2 min ago
      expect(isRecent2FAValid(recent, 5 * 60 * 1000, now)).toBe(true);
    });
  
    test('returns false after 5 min', () => {
      const old = new Date(now - 6 * 60 * 1000); // 6 min ago
      expect(isRecent2FAValid(old, 5 * 60 * 1000, now)).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isRecent2FAValid(null)).toBe(false);
    });
  });
  
  // ============================================================================
  // RESULT BUILDING TESTS
  // ============================================================================
  describe('buildVerificationSuccessResult', () => {
    test('builds success result', () => {
      const result = buildVerificationSuccessResult();
      expect(result.success).toBe(true);
      expect(result.message).toBe('verificationSuccess');
    });
  });
  
  describe('buildVerificationFailureResult', () => {
    test('builds failure result', () => {
      const result = buildVerificationFailureResult('testReason');
      expect(result.success).toBe(false);
      expect(result.message).toBe('testReason');
    });
  
    test('includes remaining when provided', () => {
      const result = buildVerificationFailureResult('invalidCode', 3);
      expect(result.remaining).toBe(3);
    });
  });
  
  describe('buildCodeNotFoundResult', () => {
    test('builds correct result', () => {
      const result = buildCodeNotFoundResult();
      expect(result.message).toBe('codeNotFound');
    });
  });
  
  describe('buildInvalidCodeResult', () => {
    test('includes remaining attempts', () => {
      const result = buildInvalidCodeResult(2);
      expect(result.message).toBe('invalidCodeWithRemaining');
      expect(result.remaining).toBe(2);
    });
  });
  
  describe('buildThrottledResult', () => {
    test('builds throttled result', () => {
      const result = buildThrottledResult();
      expect(result.message).toBe('pleasewait30seconds');
    });
  });
  
  describe('buildEmailSentResult', () => {
    test('builds email sent result', () => {
      const result = buildEmailSentResult();
      expect(result.success).toBe(true);
      expect(result.sentViaEmail).toBe(true);
    });
  });
  
  // ============================================================================
  // TOTP RESULT TESTS
  // ============================================================================
  describe('buildTotpSecretResult', () => {
    test('builds secret result', () => {
      const result = buildTotpSecretResult('otpauth://...', 'ABC123');
      expect(result.success).toBe(true);
      expect(result.otpauth).toBe('otpauth://...');
      expect(result.secretBase32).toBe('ABC123');
    });
  });
  
  describe('buildTotpEnabledResult', () => {
    test('returns enabled true', () => {
      expect(buildTotpEnabledResult(true).enabled).toBe(true);
    });
  
    test('returns enabled false', () => {
      expect(buildTotpEnabledResult(false).enabled).toBe(false);
    });
  });
  
  // ============================================================================
  // USER UPDATE TESTS
  // ============================================================================
  describe('getUserUpdateForAction', () => {
    test('returns enable update for setup', () => {
      const update = getUserUpdateForAction('setup');
      expect(update.twoFactorEnabled).toBe(true);
    });
  
    test('returns disable update for disable', () => {
      const update = getUserUpdateForAction('disable');
      expect(update.twoFactorEnabled).toBe(false);
    });
  
    test('returns empty for login', () => {
      const update = getUserUpdateForAction('login');
      expect(update.twoFactorEnabled).toBeUndefined();
    });
  });
  
  // ============================================================================
  // TOTP CONFIG TESTS
  // ============================================================================
  describe('buildTotpConfigPending', () => {
    test('builds pending config', () => {
      const config = buildTotpConfigPending('SECRET123');
      expect(config.enabled).toBe(false);
      expect(config.secretBase32).toBe('SECRET123');
    });
  });
  
  describe('buildTotpConfigEnabled', () => {
    test('builds enabled config', () => {
      const config = buildTotpConfigEnabled('SECRET123');
      expect(config.enabled).toBe(true);
      expect(config.secretBase32).toBe('SECRET123');
    });
  });
  
  // ============================================================================
  // VERIFICATION CODE DOCUMENT TESTS
  // ============================================================================
  describe('buildVerificationCodeDocument', () => {
    test('builds document', () => {
      const expiry = new Date();
      const doc = buildVerificationCodeDocument('hash123', 'login', expiry);
      expect(doc.codeHash).toBe('hash123');
      expect(doc.type).toBe('login');
      expect(doc.attempts).toBe(0);
      expect(doc.maxAttempts).toBe(5);
    });
  });
  
  // ============================================================================
  // COLLECTION PATHS TESTS
  // ============================================================================
  describe('Collection paths', () => {
    test('getVerificationCodesPath returns correct path', () => {
      expect(getVerificationCodesPath()).toBe('verification_codes');
    });
  
    test('getTotpAttemptsPath returns correct path', () => {
      expect(getTotpAttemptsPath()).toBe('totp_attempts');
    });
  
    test('getUserSecretsPath returns correct path', () => {
      expect(getUserSecretsPath('user123')).toBe('user_secrets/user123/totp/config');
    });
  });
  
  // ============================================================================
  // OTPAUTH URI TESTS
  // ============================================================================
  describe('buildOtpAuthUri', () => {
    test('builds valid URI', () => {
      const uri = buildOtpAuthUri('test@example.com', 'ABC123', 'Nar24');
      expect(uri).toContain('otpauth://totp/');
      expect(uri).toContain('secret=ABC123');
      expect(uri).toContain('issuer=Nar24');
    });
  
    test('encodes special characters', () => {
      const uri = buildOtpAuthUri('test@example.com', 'ABC123', 'Nar24');
      expect(uri).toContain(encodeURIComponent('test@example.com'));
    });
  });
  
  describe('parseOtpAuthUri', () => {
    test('parses valid URI', () => {
      const uri = 'otpauth://totp/Nar24:test@example.com?secret=ABC123&issuer=Nar24';
      const parsed = parseOtpAuthUri(uri);
      expect(parsed.secret).toBe('ABC123');
      expect(parsed.issuer).toBe('Nar24');
    });
  
    test('returns null for invalid', () => {
      expect(parseOtpAuthUri('invalid')).toBe(null);
      expect(parseOtpAuthUri(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // CLEANUP TESTS
  // ============================================================================
  describe('isExpiredCode', () => {
    const now = Date.now();
  
    test('returns true for expired', () => {
      const codeData = { expiresAt: { toMillis: () => now - 60000 } };
      expect(isExpiredCode(codeData, now)).toBe(true);
    });
  
    test('returns false for valid', () => {
      const codeData = { expiresAt: { toMillis: () => now + 60000 } };
      expect(isExpiredCode(codeData, now)).toBe(false);
    });
  });
  
  describe('isStaleAttempt', () => {
    const now = Date.now();
    const dayMs = 24 * 60 * 60 * 1000;
  
    test('returns true for old attempt', () => {
      const attemptData = { lastAttempt: new Date(now - dayMs - 1000) };
      expect(isStaleAttempt(attemptData, dayMs, now)).toBe(true);
    });
  
    test('returns false for recent attempt', () => {
      const attemptData = { lastAttempt: new Date(now - 60000) };
      expect(isStaleAttempt(attemptData, dayMs, now)).toBe(false);
    });
  
    test('returns true for null lastAttempt', () => {
      expect(isStaleAttempt({}, dayMs, now)).toBe(true);
    });
  });
  
  // ============================================================================
  // EMAIL TEMPLATE TESTS
  // ============================================================================
  describe('getEmailTemplate', () => {
    test('returns English login template', () => {
      const template = getEmailTemplate('en', 'login');
      expect(template.subject).toContain('Login');
      expect(template.title).toBe('Login Verification');
    });
  
    test('returns Turkish setup template', () => {
      const template = getEmailTemplate('tr', 'setup');
      expect(template.subject).toContain('Kurulum');
    });
  
    test('defaults to English for unknown language', () => {
      const template = getEmailTemplate('unknown', 'login');
      expect(template.subject).toContain('Login');
    });
  
    test('defaults to login for unknown type', () => {
      const template = getEmailTemplate('en', 'unknown');
      expect(template.title).toBe('Login Verification');
    });
  });
  
  describe('getEmailSubject', () => {
    test('returns correct subject', () => {
      expect(getEmailSubject('en', 'login')).toContain('Login');
      expect(getEmailSubject('tr', 'setup')).toContain('Kurulum');
      expect(getEmailSubject('ru', 'disable')).toContain('отключения');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('email 2FA verification flow', () => {
      const now = Date.now();
  
      // User requests code
      const codeExpiry = calculateCodeExpiry('login', now);
      expect(codeExpiry.getTime() - now).toBe(5 * 60 * 1000);
  
      // Build verification document
      const doc = buildVerificationCodeDocument('hashedCode', 'login', codeExpiry);
      expect(doc.attempts).toBe(0);
  
      // First wrong attempt
      let attempts = incrementAttempts(doc.attempts);
      expect(attempts).toBe(1);
      const remaining = calculateRemainingAttempts(attempts, 5);
      expect(remaining).toBe(4);
  
      // More wrong attempts
      attempts = 4;
      expect(hasExceededAttempts(attempts, 5)).toBe(false);
      expect(shouldDeleteCodeAfterAttempt(attempts, 5)).toBe(true);
  
      // After 5th wrong attempt
      attempts = 5;
      expect(hasExceededAttempts(attempts, 5)).toBe(true);
    });
  
    test('TOTP setup flow', () => {
      // Generate secret
      const secretBase32 = 'JBSWY3DPEHPK3PXP';
      const accountName = 'test@example.com';
  
      // Build pending config
      const pendingConfig = buildTotpConfigPending(secretBase32);
      expect(pendingConfig.enabled).toBe(false);
  
      // Build OTPAuth URI
      const uri = buildOtpAuthUri(accountName, secretBase32);
      expect(uri).toContain('otpauth://totp/');
  
      // After successful verification
      const enabledConfig = buildTotpConfigEnabled(secretBase32);
      expect(enabledConfig.enabled).toBe(true);
  
      // User update
      const userUpdate = getUserUpdateForAction('setup');
      expect(userUpdate.twoFactorEnabled).toBe(true);
    });
  
    test('disable 2FA flow', () => {
      const now = Date.now();
  
      // Check recent 2FA
      const recentVerification = new Date(now - 2 * 60 * 1000); // 2 min ago
      expect(isRecent2FAValid(recentVerification, RECENT_2FA_VALIDITY_MS, now)).toBe(true);
  
      // Old verification should fail
      const oldVerification = new Date(now - 10 * 60 * 1000); // 10 min ago
      expect(isRecent2FAValid(oldVerification, RECENT_2FA_VALIDITY_MS, now)).toBe(false);
  
      // User update for disable
      const userUpdate = getUserUpdateForAction('disable');
      expect(userUpdate.twoFactorEnabled).toBe(false);
    });
  
    test('throttling prevents spam', () => {
      const now = Date.now();
  
      // Just sent a code
      const lastCreated = new Date(now - 10000); // 10 sec ago
      expect(isWithinThrottleWindow(lastCreated, THROTTLE_WINDOW_MS, now)).toBe(true);
  
      // Get remaining seconds
      const remaining = getThrottleRemainingSeconds(lastCreated, THROTTLE_WINDOW_MS, now);
      expect(remaining).toBe(20); // 30 - 10
  
      // Build throttled response
      const response = buildThrottledResult();
      expect(response.success).toBe(false);
      expect(response.message).toBe('pleasewait30seconds');
    });
  });

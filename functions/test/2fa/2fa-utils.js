// functions/test/2fa/2fa-utils.js
//
// EXTRACTED PURE LOGIC from 2FA (Two-Factor Authentication) cloud functions
// These functions are EXACT COPIES of logic from the 2FA functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source 2FA functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const CODE_LENGTH = 6;
const CODE_DIGITS = 6;
const TOTP_STEP_SECONDS = 30;
const TOTP_WINDOW = 1; // Allow 1 step before/after

const VALID_ACTIONS = ['login', 'setup', 'disable'];
const DEFAULT_ACTION = 'login';

const MAX_ATTEMPTS = 5;
const THROTTLE_WINDOW_MS = 30 * 1000; // 30 seconds
const TOTP_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes
const TOTP_MAX_ATTEMPTS = 5;

const LOGIN_CODE_TTL_MINUTES = 5;
const SETUP_CODE_TTL_MINUTES = 10;

const RECENT_2FA_VALIDITY_MS = 5 * 60 * 1000; // 5 minutes

const ISSUER = 'Nar24';

// ============================================================================
// CODE VALIDATION
// ============================================================================

function sanitizeCode(code) {
  if (!code) return '';
  return String(code).replace(/\D/g, '');
}

function validateCode(code) {
  const sanitized = sanitizeCode(code);

  if (!sanitized) {
    return { isValid: false, reason: 'missing', message: '6-digit code required.' };
  }

  if (sanitized.length !== CODE_LENGTH) {
    return { isValid: false, reason: 'wrong_length', message: '6-digit code required.' };
  }

  return { isValid: true, sanitizedCode: sanitized };
}

function isValidCode(code) {
  return validateCode(code).isValid;
}

// ============================================================================
// ACTION VALIDATION
// ============================================================================

function validateAction(action) {
  if (!action) {
    return { isValid: true, action: DEFAULT_ACTION };
  }

  if (!VALID_ACTIONS.includes(action)) {
    return { isValid: true, action: DEFAULT_ACTION }; // Fallback to default
  }

  return { isValid: true, action };
}

function getValidAction(action) {
  return VALID_ACTIONS.includes(action) ? action : DEFAULT_ACTION;
}

function isValidAction(action) {
  return VALID_ACTIONS.includes(action);
}

// ============================================================================
// CODE EXPIRATION
// ============================================================================

function isCodeExpired(expiresAt, nowMs = Date.now()) {
  if (!expiresAt) return true;

  const expiryMs = expiresAt.toMillis ? expiresAt.toMillis() : (expiresAt instanceof Date ? expiresAt.getTime() : expiresAt);

  return nowMs > expiryMs;
}

function calculateCodeExpiry(type, nowMs = Date.now()) {
  const ttlMinutes = type === 'login' ? LOGIN_CODE_TTL_MINUTES : SETUP_CODE_TTL_MINUTES;
  return new Date(nowMs + ttlMinutes * 60 * 1000);
}

function getCodeTtlMinutes(type) {
  return type === 'login' ? LOGIN_CODE_TTL_MINUTES : SETUP_CODE_TTL_MINUTES;
}

// ============================================================================
// ATTEMPT TRACKING
// ============================================================================

function hasExceededAttempts(attempts, maxAttempts = MAX_ATTEMPTS) {
  return (attempts || 0) >= maxAttempts;
}

function calculateRemainingAttempts(attempts, maxAttempts = MAX_ATTEMPTS) {
  return Math.max(maxAttempts - (attempts || 0), 0);
}

function shouldDeleteCodeAfterAttempt(attempts, maxAttempts = MAX_ATTEMPTS) {
  return (attempts || 0) + 1 >= maxAttempts;
}

function incrementAttempts(currentAttempts) {
  return (currentAttempts || 0) + 1;
}

// ============================================================================
// THROTTLING
// ============================================================================

function isWithinThrottleWindow(lastCreated, windowMs = THROTTLE_WINDOW_MS, nowMs = Date.now()) {
  if (!lastCreated) return false;

  const lastMs = lastCreated instanceof Date ? lastCreated.getTime() : (lastCreated.toDate ? lastCreated.toDate().getTime() : lastCreated);

  return nowMs - lastMs < windowMs;
}

function getThrottleRemainingSeconds(lastCreated, windowMs = THROTTLE_WINDOW_MS, nowMs = Date.now()) {
  if (!lastCreated) return 0;

  const lastMs = lastCreated instanceof Date ? lastCreated.getTime() : (lastCreated.toDate ? lastCreated.toDate().getTime() : lastCreated);

  const elapsed = nowMs - lastMs;
  const remaining = windowMs - elapsed;

  return Math.max(Math.ceil(remaining / 1000), 0);
}

// ============================================================================
// TOTP RATE LIMITING
// ============================================================================

function isWithinTotpRateLimitWindow(lastAttempt, nowMs = Date.now()) {
  if (!lastAttempt) return false;

  const lastMs = lastAttempt instanceof Date ? lastAttempt.getTime() : (lastAttempt.toDate ? lastAttempt.toDate().getTime() : lastAttempt);

  return nowMs - lastMs <= TOTP_RATE_LIMIT_WINDOW_MS;
}

function shouldResetTotpAttempts(lastAttempt, nowMs = Date.now()) {
  return !isWithinTotpRateLimitWindow(lastAttempt, nowMs);
}

function isTotpRateLimited(attempts, lastAttempt, nowMs = Date.now()) {
  // If outside rate limit window, not limited (attempts reset)
  if (!isWithinTotpRateLimitWindow(lastAttempt, nowMs)) {
    return false;
  }
  return attempts >= TOTP_MAX_ATTEMPTS;
}

// ============================================================================
// RECENT 2FA VALIDATION
// ============================================================================

function isRecent2FAValid(lastTwoFactorVerification, validityMs = RECENT_2FA_VALIDITY_MS, nowMs = Date.now()) {
  if (!lastTwoFactorVerification) return false;

  const lastMs = lastTwoFactorVerification instanceof Date ? lastTwoFactorVerification.getTime() : (lastTwoFactorVerification.toDate ? lastTwoFactorVerification.toDate().getTime() : lastTwoFactorVerification);

  return nowMs - lastMs <= validityMs;
}

function getRecent2FARemainingMs(lastTwoFactorVerification, validityMs = RECENT_2FA_VALIDITY_MS, nowMs = Date.now()) {
  if (!lastTwoFactorVerification) return 0;

  const lastMs = lastTwoFactorVerification instanceof Date ? lastTwoFactorVerification.getTime() : (lastTwoFactorVerification.toDate ? lastTwoFactorVerification.toDate().getTime() : lastTwoFactorVerification);

  const elapsed = nowMs - lastMs;
  return Math.max(validityMs - elapsed, 0);
}

// ============================================================================
// VERIFICATION RESULT BUILDING
// ============================================================================

function buildVerificationSuccessResult(action) {
  return { success: true, message: 'verificationSuccess' };
}

function buildVerificationFailureResult(reason, remaining = null) {
  const result = { success: false, message: reason };
  if (remaining !== null) {
    result.remaining = remaining;
  }
  return result;
}

function buildCodeNotFoundResult() {
  return { success: false, message: 'codeNotFound' };
}

function buildCodeExpiredResult() {
  return { success: false, message: 'codeExpired' };
}

function buildTooManyAttemptsResult() {
  return { success: false, message: 'tooManyAttempts' };
}

function buildInvalidCodeResult(remaining) {
  return { success: false, message: 'invalidCodeWithRemaining', remaining };
}

function buildThrottledResult() {
  return { success: false, message: 'pleasewait30seconds' };
}

function buildEmailSentResult() {
  return { success: true, sentViaEmail: true, message: 'emailCodeSent' };
}

// ============================================================================
// TOTP RESULT BUILDING
// ============================================================================

function buildTotpSuccessResult() {
  return { success: true };
}

function buildTotpSecretResult(otpauth, secretBase32) {
  return { success: true, otpauth, secretBase32 };
}

function buildTotpEnabledResult(enabled) {
  return { enabled: !!enabled };
}

// ============================================================================
// USER DATA UPDATES
// ============================================================================

function buildEnableTwoFactorUpdate() {
  return {
    twoFactorEnabled: true,
  };
}

function buildDisableTwoFactorUpdate() {
  return {
    twoFactorEnabled: false,
  };
}

function buildLoginVerificationUpdate() {
  return {};
}

function getUserUpdateForAction(action) {
  switch (action) {
    case 'setup':
      return buildEnableTwoFactorUpdate();
    case 'disable':
      return buildDisableTwoFactorUpdate();
    default:
      return buildLoginVerificationUpdate();
  }
}

// ============================================================================
// TOTP CONFIG BUILDING
// ============================================================================

function buildTotpConfigPending(secretBase32) {
  return {
    enabled: false,
    secretBase32,
  };
}

function buildTotpConfigEnabled(secretBase32) {
  return {
    enabled: true,
    secretBase32,
  };
}

// ============================================================================
// VERIFICATION CODE DOCUMENT
// ============================================================================

function buildVerificationCodeDocument(codeHash, type, expiresAt) {
  return {
    codeHash,
    type,
    attempts: 0,
    maxAttempts: MAX_ATTEMPTS,
    expiresAt,
  };
}

// ============================================================================
// COLLECTION PATHS
// ============================================================================

function getVerificationCodesPath() {
  return 'verification_codes';
}

function getTotpAttemptsPath() {
  return 'totp_attempts';
}

function getUserSecretsPath(uid) {
  return `user_secrets/${uid}/totp/config`;
}

function getLegacyTotpPath(uid) {
  return `users/${uid}`;
}

// ============================================================================
// OTPAUTH URI BUILDING
// ============================================================================

function buildOtpAuthUri(accountName, secretBase32, issuer = ISSUER) {
  const encodedIssuer = encodeURIComponent(issuer);
  const encodedAccount = encodeURIComponent(accountName);
  return `otpauth://totp/${encodedIssuer}:${encodedAccount}?secret=${secretBase32}&issuer=${encodedIssuer}`;
}

function parseOtpAuthUri(uri) {
  if (!uri || !uri.startsWith('otpauth://totp/')) return null;

  try {
    const url = new URL(uri);
    const secret = url.searchParams.get('secret');
    const issuer = url.searchParams.get('issuer');
    const label = decodeURIComponent(url.pathname.replace('/totp/', ''));

    return { secret, issuer, label };
  } catch {
    return null;
  }
}

// ============================================================================
// CLEANUP HELPERS
// ============================================================================

function isExpiredCode(codeData, nowMs = Date.now()) {
  return isCodeExpired(codeData.expiresAt, nowMs);
}

function isStaleAttempt(attemptData, staleThresholdMs = 24 * 60 * 60 * 1000, nowMs = Date.now()) {
  if (!attemptData?.lastAttempt) return true;

  const lastMs = attemptData.lastAttempt instanceof Date ? attemptData.lastAttempt.getTime() : (attemptData.lastAttempt.toDate ? attemptData.lastAttempt.toDate().getTime() : attemptData.lastAttempt);

  return nowMs - lastMs > staleThresholdMs;
}

// ============================================================================
// EMAIL TEMPLATE HELPERS
// ============================================================================

const EMAIL_TEMPLATES = {
  en: {
    login: {
      subject: 'Nar24 - Login Verification Code',
      title: 'Login Verification',
      message: 'Use this code to verify your login:',
    },
    setup: {
      subject: 'Nar24 - 2FA Setup Code',
      title: '2FA Setup',
      message: 'Use this code to enable two-factor authentication:',
    },
    disable: {
      subject: 'Nar24 - Disable 2FA Code',
      title: 'Disable 2FA',
      message: 'Use this code to disable two-factor authentication:',
    },
  },
  tr: {
    login: {
      subject: 'Nar24 - Giriş Doğrulama Kodu',
      title: 'Giriş Doğrulama',
      message: 'Girişinizi doğrulamak için bu kodu kullanın:',
    },
    setup: {
      subject: 'Nar24 - 2FA Kurulum Kodu',
      title: '2FA Kurulum',
      message: 'İki faktörlü kimlik doğrulamayı etkinleştirmek için bu kodu kullanın:',
    },
    disable: {
      subject: 'Nar24 - 2FA Devre Dışı Bırakma Kodu',
      title: '2FA Devre Dışı',
      message: 'İki faktörlü kimlik doğrulamayı devre dışı bırakmak için bu kodu kullanın:',
    },
  },
  ru: {
    login: {
      subject: 'Nar24 - Код подтверждения входа',
      title: 'Подтверждение входа',
      message: 'Используйте этот код для подтверждения входа:',
    },
    setup: {
      subject: 'Nar24 - Код настройки 2FA',
      title: 'Настройка 2FA',
      message: 'Используйте этот код для включения двухфакторной аутентификации:',
    },
    disable: {
      subject: 'Nar24 - Код отключения 2FA',
      title: 'Отключение 2FA',
      message: 'Используйте этот код для отключения двухфакторной аутентификации:',
    },
  },
};

function getEmailTemplate(language, type) {
  const lang = EMAIL_TEMPLATES[language] ? language : 'en';
  const action = VALID_ACTIONS.includes(type) ? type : 'login';
  return EMAIL_TEMPLATES[lang][action];
}

function getEmailSubject(language, type) {
  return getEmailTemplate(language, type).subject;
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  CODE_LENGTH,
  CODE_DIGITS,
  TOTP_STEP_SECONDS,
  TOTP_WINDOW,
  VALID_ACTIONS,
  DEFAULT_ACTION,
  MAX_ATTEMPTS,
  THROTTLE_WINDOW_MS,
  TOTP_RATE_LIMIT_WINDOW_MS,
  TOTP_MAX_ATTEMPTS,
  LOGIN_CODE_TTL_MINUTES,
  SETUP_CODE_TTL_MINUTES,
  RECENT_2FA_VALIDITY_MS,
  ISSUER,
  EMAIL_TEMPLATES,

  // Code validation
  sanitizeCode,
  validateCode,
  isValidCode,

  // Action validation
  validateAction,
  getValidAction,
  isValidAction,

  // Code expiration
  isCodeExpired,
  calculateCodeExpiry,
  getCodeTtlMinutes,

  // Attempt tracking
  hasExceededAttempts,
  calculateRemainingAttempts,
  shouldDeleteCodeAfterAttempt,
  incrementAttempts,

  // Throttling
  isWithinThrottleWindow,
  getThrottleRemainingSeconds,

  // TOTP rate limiting
  isWithinTotpRateLimitWindow,
  shouldResetTotpAttempts,
  isTotpRateLimited,

  // Recent 2FA
  isRecent2FAValid,
  getRecent2FARemainingMs,

  // Verification results
  buildVerificationSuccessResult,
  buildVerificationFailureResult,
  buildCodeNotFoundResult,
  buildCodeExpiredResult,
  buildTooManyAttemptsResult,
  buildInvalidCodeResult,
  buildThrottledResult,
  buildEmailSentResult,

  // TOTP results
  buildTotpSuccessResult,
  buildTotpSecretResult,
  buildTotpEnabledResult,

  // User updates
  buildEnableTwoFactorUpdate,
  buildDisableTwoFactorUpdate,
  buildLoginVerificationUpdate,
  getUserUpdateForAction,

  // TOTP config
  buildTotpConfigPending,
  buildTotpConfigEnabled,

  // Verification code document
  buildVerificationCodeDocument,

  // Collection paths
  getVerificationCodesPath,
  getTotpAttemptsPath,
  getUserSecretsPath,
  getLegacyTotpPath,

  // OTPAuth URI
  buildOtpAuthUri,
  parseOtpAuthUri,

  // Cleanup
  isExpiredCode,
  isStaleAttempt,

  // Email templates
  getEmailTemplate,
  getEmailSubject,
};

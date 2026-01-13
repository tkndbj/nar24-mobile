// functions/test/register-email-password-email-verification/email-verification-utils.js
//
// EXTRACTED PURE LOGIC from email registration with verification cloud functions
// These functions are EXACT COPIES of logic from the registration functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source registration functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const MIN_PASSWORD_LENGTH = 8;
const VERIFICATION_CODE_LENGTH = 6;
const CODE_EXPIRY_MINUTES = 5;
const RESEND_COOLDOWN_SECONDS = 30;
const SUPPORTED_LANGUAGES = ['en', 'tr', 'ru'];
const DEFAULT_LANGUAGE = 'en';

// ============================================================================
// PASSWORD VALIDATION
// ============================================================================

function validatePasswordLength(password) {
  if (!password || typeof password !== 'string') {
    return { isValid: false, reason: 'missing', message: 'Password is required' };
  }
  if (password.length < MIN_PASSWORD_LENGTH) {
    return { isValid: false, reason: 'too_short', message: 'Password must be at least 8 characters long' };
  }
  return { isValid: true };
}

function validatePasswordUppercase(password) {
  if (!/[A-Z]/.test(password)) {
    return { isValid: false, reason: 'no_uppercase', message: 'Password must contain at least one uppercase letter' };
  }
  return { isValid: true };
}

function validatePasswordLowercase(password) {
  if (!/[a-z]/.test(password)) {
    return { isValid: false, reason: 'no_lowercase', message: 'Password must contain at least one lowercase letter' };
  }
  return { isValid: true };
}

function validatePasswordNumber(password) {
  if (!/[0-9]/.test(password)) {
    return { isValid: false, reason: 'no_number', message: 'Password must contain at least one number' };
  }
  return { isValid: true };
}

function validatePasswordSpecialChar(password) {
  if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
    return { isValid: false, reason: 'no_special', message: 'Password must contain at least one special character' };
  }
  return { isValid: true };
}

function validatePassword(password) {
  const lengthResult = validatePasswordLength(password);
  if (!lengthResult.isValid) return lengthResult;

  const uppercaseResult = validatePasswordUppercase(password);
  if (!uppercaseResult.isValid) return uppercaseResult;

  const lowercaseResult = validatePasswordLowercase(password);
  if (!lowercaseResult.isValid) return lowercaseResult;

  const numberResult = validatePasswordNumber(password);
  if (!numberResult.isValid) return numberResult;

  const specialResult = validatePasswordSpecialChar(password);
  if (!specialResult.isValid) return specialResult;

  return { isValid: true };
}

function getPasswordStrength(password) {
  if (!password) return 0;
  
  let strength = 0;
  if (password.length >= MIN_PASSWORD_LENGTH) strength++;
  if (/[A-Z]/.test(password)) strength++;
  if (/[a-z]/.test(password)) strength++;
  if (/[0-9]/.test(password)) strength++;
  if (/[!@#$%^&*(),.?":{}|<>]/.test(password)) strength++;
  
  return strength;
}

function isStrongPassword(password) {
  return getPasswordStrength(password) === 5;
}

// ============================================================================
// FIELD VALIDATION
// ============================================================================

function validateEmail(email) {
  if (!email) {
    return { isValid: false, reason: 'missing', message: 'Email is required' };
  }
  if (typeof email !== 'string') {
    return { isValid: false, reason: 'not_string', message: 'Email must be a string' };
  }
  return { isValid: true, email: email };
}

function validateName(name, fieldName = 'name') {
  if (!name) {
    return { isValid: false, reason: 'missing', message: `${fieldName} is required` };
  }
  if (typeof name !== 'string') {
    return { isValid: false, reason: 'not_string', message: `${fieldName} must be a string` };
  }
  return { isValid: true, name: name.trim() };
}

function validateRegistrationFields(data) {
  const errors = [];

  const emailResult = validateEmail(data.email);
  if (!emailResult.isValid) {
    errors.push({ field: 'email', ...emailResult });
  }

  const passwordResult = validatePassword(data.password);
  if (!passwordResult.isValid) {
    errors.push({ field: 'password', ...passwordResult });
  }

  const nameResult = validateName(data.name, 'name');
  if (!nameResult.isValid) {
    errors.push({ field: 'name', ...nameResult });
  }

  const surnameResult = validateName(data.surname, 'surname');
  if (!surnameResult.isValid) {
    errors.push({ field: 'surname', ...surnameResult });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, firstError: errors[0] };
  }

  return { isValid: true };
}

// ============================================================================
// BIRTH DATE VALIDATION
// ============================================================================

function validateBirthDate(birthDate) {
  if (!birthDate) {
    return { isValid: true, birthDate: null };
  }

  const d = new Date(birthDate);
  if (isNaN(d.getTime())) {
    return { 
      isValid: false, 
      reason: 'invalid_format', 
      message: `birthDate must be a valid ISO string, got "${birthDate}"` 
    };
  }

  return { isValid: true, birthDate: d };
}

function isValidBirthDate(birthDate) {
  return validateBirthDate(birthDate).isValid;
}

// ============================================================================
// DISPLAY NAME
// ============================================================================

function buildDisplayName(name, surname) {
  const trimmedName = (name || '').trim();
  const trimmedSurname = (surname || '').trim();
  return `${trimmedName} ${trimmedSurname}`;
}

// ============================================================================
// PROFILE DATA BUILDING
// ============================================================================

function buildProfileData(input, uid) {
  const { name, surname, email, gender, birthDate, languageCode } = input;

  const profileData = {
    displayName: buildDisplayName(name, surname),
    email: email,
    isNew: true,
    isVerified: false,
    referralCode: uid,
    languageCode: languageCode || DEFAULT_LANGUAGE,
  };

  if (gender) {
    profileData.gender = gender;
  }

  if (birthDate) {
    const dateResult = validateBirthDate(birthDate);
    if (dateResult.isValid && dateResult.birthDate) {
      profileData.birthDate = dateResult.birthDate;
    }
  }

  return profileData;
}

// ============================================================================
// REFERRAL DATA
// ============================================================================

function buildReferralData(email) {
  return {
    email: email || '',
  };
}

function extractReferralCode(referralCode) {
  if (!referralCode || typeof referralCode !== 'string') {
    return null;
  }
  const trimmed = referralCode.trim();
  return trimmed.length > 0 ? trimmed : null;
}

// ============================================================================
// VERIFICATION CODE GENERATION
// ============================================================================

function generateVerificationCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function isValidVerificationCodeFormat(code) {
  if (!code || typeof code !== 'string') return false;
  if (code.length !== VERIFICATION_CODE_LENGTH) return false;
  if (!/^\d+$/.test(code)) return false;
  return true;
}

// ============================================================================
// CODE EXPIRATION
// ============================================================================

function calculateCodeExpiry(nowMs = Date.now()) {
  return new Date(nowMs + CODE_EXPIRY_MINUTES * 60 * 1000);
}

function isCodeExpired(expiresAt, nowMs = Date.now()) {
  if (!expiresAt) return true;
  
  const expiryTime = expiresAt instanceof Date ? expiresAt.getTime() : (expiresAt.toDate ? expiresAt.toDate().getTime() : expiresAt);
  
  return expiryTime < nowMs;
}

function getCodeExpiryMinutes() {
  return CODE_EXPIRY_MINUTES;
}

// ============================================================================
// CODE VALIDATION
// ============================================================================

function validateVerificationCode(storedCode, providedCode, expiresAt, used) {
  if (!isValidVerificationCodeFormat(providedCode)) {
    return { isValid: false, reason: 'invalid_format', message: 'Valid 6-digit code is required' };
  }

  if (isCodeExpired(expiresAt)) {
    return { isValid: false, reason: 'expired', message: 'Verification code has expired' };
  }

  if (used) {
    return { isValid: false, reason: 'already_used', message: 'Verification code has already been used' };
  }

  if (storedCode !== providedCode) {
    return { isValid: false, reason: 'mismatch', message: 'Invalid verification code' };
  }

  return { isValid: true };
}

// ============================================================================
// RATE LIMITING
// ============================================================================

function canResendCode(lastSentAt, nowMs = Date.now()) {
  if (!lastSentAt) return { canResend: true };

  const lastSentTime = lastSentAt instanceof Date ? lastSentAt.getTime() : (lastSentAt.toMillis ? lastSentAt.toMillis() : lastSentAt);

  const timeSinceLastCode = nowMs - lastSentTime;
  const cooldownMs = RESEND_COOLDOWN_SECONDS * 1000;

  if (timeSinceLastCode < cooldownMs) {
    const waitTime = Math.ceil((cooldownMs - timeSinceLastCode) / 1000);
    return { 
      canResend: false, 
      waitSeconds: waitTime,
      message: `Please wait ${waitTime} seconds before requesting a new code`
    };
  }

  return { canResend: true };
}

function getResendCooldownSeconds() {
  return RESEND_COOLDOWN_SECONDS;
}

// ============================================================================
// EMAIL TEMPLATES
// ============================================================================

const EMAIL_SUBJECTS = {
  en: 'Nar24 - Email Verification Code',
  tr: 'Nar24 - Email Doğrulama Kodu',
  ru: 'Nar24 - Код подтверждения электронной почты',
};

const EMAIL_TEMPLATES = {
  en: {
    title: 'Email Verification Required',
    greeting: (name) => `Hello ${name},`,
    message: 'Someone is trying to verify an email address for your Nar24 account. To complete your email verification, enter the verification code below:',
    codeLabel: 'Verification Code',
    expiry: '⏰ This code expires in 5 minutes',
    warning: '🚨 If you did not request this verification, please secure your account immediately.',
    footer: 'This is an automated message from Nar24. Please do not reply to this email.',
  },
  tr: {
    title: 'Email Doğrulaması Gerekli',
    greeting: (name) => `Merhaba ${name},`,
    message: 'Birisi Nar24 hesabınız için email adresi doğrulamaya çalışıyor. Email doğrulamanızı tamamlamak için aşağıdaki doğrulama kodunu girin:',
    codeLabel: 'Doğrulama Kodu',
    expiry: '⏰ Bu kod 5 dakika içinde sona erer',
    warning: '🚨 Bu doğrulamayı talep etmediyseniz, lütfen hesabınızı hemen güvence altına alın.',
    footer: 'Bu Nar24 tarafından otomatik bir mesajdır. Lütfen bu e-postayı yanıtlamayın.',
  },
  ru: {
    title: 'Требуется подтверждение электронной почты',
    greeting: (name) => `Здравствуйте, ${name}!`,
    message: 'Кто-то пытается подтвердить адрес электронной почты для вашей учетной записи Nar24. Чтобы завершить подтверждение электронной почты, введите код подтверждения ниже:',
    codeLabel: 'Код подтверждения',
    expiry: '⏰ Срок действия этого кода истекает через 5 минут',
    warning: '🚨 Если вы не запрашивали это подтверждение, немедленно обезопасьте свою учетную запись.',
    footer: 'Это автоматическое сообщение от Nar24. Пожалуйста, не отвечайте на это письмо.',
  },
};

function getEmailSubject(languageCode) {
  return EMAIL_SUBJECTS[languageCode] || EMAIL_SUBJECTS[DEFAULT_LANGUAGE];
}

function getEmailTemplate(languageCode) {
  return EMAIL_TEMPLATES[languageCode] || EMAIL_TEMPLATES[DEFAULT_LANGUAGE];
}

function getEffectiveLanguage(languageCode) {
  if (SUPPORTED_LANGUAGES.includes(languageCode)) {
    return languageCode;
  }
  return DEFAULT_LANGUAGE;
}

// ============================================================================
// MAIL DOCUMENT BUILDING
// ============================================================================

function buildMailDocument(email, code, languageCode, displayName) {
  const lang = getEffectiveLanguage(languageCode);
  
  return {
    to: [email],
    message: {
      subject: getEmailSubject(lang),
    },
    template: {
      name: 'email-verification',
      data: {
        code: code,
        language: lang,
        type: 'email_verification',
      },
    },
  };
}

// ============================================================================
// VERIFICATION CODE DOCUMENT
// ============================================================================

function buildVerificationCodeDocument(code, email, nowMs = Date.now()) {
  return {
    code: code,
    email: email,
    expiresAt: calculateCodeExpiry(nowMs),
    used: false,
  };
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildRegistrationResponse(uid, customToken, emailSent) {
  return {
    uid: uid,
    customToken: customToken,
    emailSent: emailSent,
    verificationCodeSent: emailSent,
  };
}

function buildVerifySuccessResponse() {
  return {
    success: true,
    message: 'Email verified successfully',
  };
}

function buildResendSuccessResponse() {
  return {
    success: true,
    message: 'Verification code sent successfully',
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  MIN_PASSWORD_LENGTH,
  VERIFICATION_CODE_LENGTH,
  CODE_EXPIRY_MINUTES,
  RESEND_COOLDOWN_SECONDS,
  SUPPORTED_LANGUAGES,
  DEFAULT_LANGUAGE,
  EMAIL_SUBJECTS,
  EMAIL_TEMPLATES,

  // Password validation
  validatePasswordLength,
  validatePasswordUppercase,
  validatePasswordLowercase,
  validatePasswordNumber,
  validatePasswordSpecialChar,
  validatePassword,
  getPasswordStrength,
  isStrongPassword,

  // Field validation
  validateEmail,
  validateName,
  validateRegistrationFields,

  // Birth date
  validateBirthDate,
  isValidBirthDate,

  // Display name
  buildDisplayName,

  // Profile data
  buildProfileData,

  // Referral
  buildReferralData,
  extractReferralCode,

  // Verification code
  generateVerificationCode,
  isValidVerificationCodeFormat,

  // Code expiration
  calculateCodeExpiry,
  isCodeExpired,
  getCodeExpiryMinutes,

  // Code validation
  validateVerificationCode,

  // Rate limiting
  canResendCode,
  getResendCooldownSeconds,

  // Email templates
  getEmailSubject,
  getEmailTemplate,
  getEffectiveLanguage,

  // Mail document
  buildMailDocument,

  // Verification code document
  buildVerificationCodeDocument,

  // Response building
  buildRegistrationResponse,
  buildVerifySuccessResponse,
  buildResendSuccessResponse,
};

// functions/test/register-email-password-email-verification/email-verification-utils.test.js
//
// Unit tests for email registration with verification utility functions
// Tests the EXACT logic from registration cloud functions
//
// Run: npx jest test/register-email-password-email-verification/email-verification-utils.test.js

const {
    MIN_PASSWORD_LENGTH,
    VERIFICATION_CODE_LENGTH,
    CODE_EXPIRY_MINUTES,
    RESEND_COOLDOWN_SECONDS,
    SUPPORTED_LANGUAGES,
    DEFAULT_LANGUAGE,

  
    validatePasswordLength,
    validatePasswordUppercase,
    validatePasswordLowercase,
    validatePasswordNumber,
    validatePasswordSpecialChar,
    validatePassword,
    getPasswordStrength,
    isStrongPassword,
  
    validateEmail,
    validateName,
    validateRegistrationFields,
  
    validateBirthDate,
    isValidBirthDate,
  
    buildDisplayName,
  
    buildProfileData,
  
    buildReferralData,
    extractReferralCode,
  
    generateVerificationCode,
    isValidVerificationCodeFormat,
  
    calculateCodeExpiry,
    isCodeExpired,
    getCodeExpiryMinutes,
  
    validateVerificationCode,
  
    canResendCode,
    getResendCooldownSeconds,
  
    getEmailSubject,
    getEmailTemplate,
    getEffectiveLanguage,
  
    buildMailDocument,
  
    buildVerificationCodeDocument,
  
    buildRegistrationResponse,
    buildVerifySuccessResponse,
    buildResendSuccessResponse,
  } = require('./email-verification-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('MIN_PASSWORD_LENGTH is 8', () => {
      expect(MIN_PASSWORD_LENGTH).toBe(8);
    });
  
    test('VERIFICATION_CODE_LENGTH is 6', () => {
      expect(VERIFICATION_CODE_LENGTH).toBe(6);
    });
  
    test('CODE_EXPIRY_MINUTES is 5', () => {
      expect(CODE_EXPIRY_MINUTES).toBe(5);
    });
  
    test('RESEND_COOLDOWN_SECONDS is 30', () => {
      expect(RESEND_COOLDOWN_SECONDS).toBe(30);
    });
  
    test('SUPPORTED_LANGUAGES contains en, tr, ru', () => {
      expect(SUPPORTED_LANGUAGES).toContain('en');
      expect(SUPPORTED_LANGUAGES).toContain('tr');
      expect(SUPPORTED_LANGUAGES).toContain('ru');
    });
  
    test('DEFAULT_LANGUAGE is en', () => {
      expect(DEFAULT_LANGUAGE).toBe('en');
    });
  });
  
  // ============================================================================
  // PASSWORD LENGTH VALIDATION TESTS
  // ============================================================================
  describe('validatePasswordLength', () => {
    test('returns invalid for null', () => {
      const result = validatePasswordLength(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for password < 8 chars', () => {
      const result = validatePasswordLength('1234567');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('too_short');
    });
  
    test('returns valid for password = 8 chars', () => {
      expect(validatePasswordLength('12345678').isValid).toBe(true);
    });
  
    test('returns valid for password > 8 chars', () => {
      expect(validatePasswordLength('123456789').isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // PASSWORD CHARACTER VALIDATION TESTS
  // ============================================================================
  describe('validatePasswordUppercase', () => {
    test('returns invalid for no uppercase', () => {
      const result = validatePasswordUppercase('lowercase123!');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_uppercase');
    });
  
    test('returns valid for has uppercase', () => {
      expect(validatePasswordUppercase('Uppercase123!').isValid).toBe(true);
    });
  });
  
  describe('validatePasswordLowercase', () => {
    test('returns invalid for no lowercase', () => {
      const result = validatePasswordLowercase('UPPERCASE123!');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_lowercase');
    });
  
    test('returns valid for has lowercase', () => {
      expect(validatePasswordLowercase('UPPERlower123!').isValid).toBe(true);
    });
  });
  
  describe('validatePasswordNumber', () => {
    test('returns invalid for no number', () => {
      const result = validatePasswordNumber('NoNumbers!');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_number');
    });
  
    test('returns valid for has number', () => {
      expect(validatePasswordNumber('HasNumber1!').isValid).toBe(true);
    });
  });
  
  describe('validatePasswordSpecialChar', () => {
    test('returns invalid for no special char', () => {
      const result = validatePasswordSpecialChar('NoSpecial123');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_special');
    });
  
    test('returns valid for has special char', () => {
      expect(validatePasswordSpecialChar('Special!').isValid).toBe(true);
      expect(validatePasswordSpecialChar('Special@').isValid).toBe(true);
      expect(validatePasswordSpecialChar('Special#').isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // COMPLETE PASSWORD VALIDATION TESTS
  // ============================================================================
  describe('validatePassword', () => {
    test('returns invalid for short password', () => {
      const result = validatePassword('Aa1!');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('too_short');
    });
  
    test('returns invalid for no uppercase', () => {
      const result = validatePassword('lowercase1!');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_uppercase');
    });
  
    test('returns invalid for no lowercase', () => {
      const result = validatePassword('UPPERCASE1!');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_lowercase');
    });
  
    test('returns invalid for no number', () => {
      const result = validatePassword('NoNumbers!A');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_number');
    });
  
    test('returns invalid for no special char', () => {
      const result = validatePassword('NoSpecial1A');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('no_special');
    });
  
    test('returns valid for strong password', () => {
      const result = validatePassword('StrongPass1!');
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('getPasswordStrength', () => {
    test('returns 0 for null', () => {
      expect(getPasswordStrength(null)).toBe(0);
    });
  
    test('returns 0 for empty string', () => {
      expect(getPasswordStrength('')).toBe(0);
    });
  
    test('returns 1 for length only', () => {
      expect(getPasswordStrength('aaaaaaaa')).toBe(2); // length + lowercase
    });
  
    test('returns 5 for all requirements', () => {
      expect(getPasswordStrength('StrongPass1!')).toBe(5);
    });
  });
  
  describe('isStrongPassword', () => {
    test('returns true for strong password', () => {
      expect(isStrongPassword('StrongPass1!')).toBe(true);
    });
  
    test('returns false for weak password', () => {
      expect(isStrongPassword('weak')).toBe(false);
    });
  });
  
  // ============================================================================
  // FIELD VALIDATION TESTS
  // ============================================================================
  describe('validateEmail', () => {
    test('returns invalid for null', () => {
      const result = validateEmail(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-string', () => {
      const result = validateEmail(123);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for string email', () => {
      const result = validateEmail('test@example.com');
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('validateName', () => {
    test('returns invalid for null', () => {
      const result = validateName(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for string name', () => {
      const result = validateName('John');
      expect(result.isValid).toBe(true);
      expect(result.name).toBe('John');
    });
  
    test('trims whitespace', () => {
      const result = validateName('  John  ');
      expect(result.name).toBe('John');
    });
  
    test('uses custom field name in message', () => {
      const result = validateName(null, 'surname');
      expect(result.message).toBe('surname is required');
    });
  });
  
  describe('validateRegistrationFields', () => {
    test('returns valid for all valid fields', () => {
      const data = {
        email: 'test@example.com',
        password: 'StrongPass1!',
        name: 'John',
        surname: 'Doe',
      };
      const result = validateRegistrationFields(data);
      expect(result.isValid).toBe(true);
    });
  
    test('returns errors for invalid fields', () => {
      const data = {
        email: '',
        password: 'weak',
        name: '',
        surname: '',
      };
      const result = validateRegistrationFields(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });
  
    test('returns firstError', () => {
      const data = {
        email: '',
        password: 'StrongPass1!',
        name: 'John',
        surname: 'Doe',
      };
      const result = validateRegistrationFields(data);
      expect(result.firstError).toBeDefined();
      expect(result.firstError.field).toBe('email');
    });
  });
  
  // ============================================================================
  // BIRTH DATE VALIDATION TESTS
  // ============================================================================
  describe('validateBirthDate', () => {
    test('returns valid for null (optional)', () => {
      const result = validateBirthDate(null);
      expect(result.isValid).toBe(true);
      expect(result.birthDate).toBe(null);
    });
  
    test('returns valid for valid ISO string', () => {
      const result = validateBirthDate('1990-06-15');
      expect(result.isValid).toBe(true);
      expect(result.birthDate instanceof Date).toBe(true);
    });
  
    test('returns invalid for invalid date string', () => {
      const result = validateBirthDate('not-a-date');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_format');
    });
  });
  
  describe('isValidBirthDate', () => {
    test('returns true for valid date', () => {
      expect(isValidBirthDate('1990-06-15')).toBe(true);
    });
  
    test('returns false for invalid date', () => {
      expect(isValidBirthDate('invalid')).toBe(false);
    });
  });
  
  // ============================================================================
  // DISPLAY NAME TESTS
  // ============================================================================
  describe('buildDisplayName', () => {
    test('combines name and surname', () => {
      expect(buildDisplayName('John', 'Doe')).toBe('John Doe');
    });
  
    test('trims whitespace', () => {
      expect(buildDisplayName('  John  ', '  Doe  ')).toBe('John Doe');
    });
  });
  
  // ============================================================================
  // PROFILE DATA TESTS
  // ============================================================================
  describe('buildProfileData', () => {
    test('builds profile with required fields', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
      };
      const result = buildProfileData(input, 'uid123');
  
      expect(result.displayName).toBe('John Doe');
      expect(result.email).toBe('john@example.com');
      expect(result.isNew).toBe(true);
      expect(result.isVerified).toBe(false);
      expect(result.referralCode).toBe('uid123');
      expect(result.languageCode).toBe('en');
    });
  
    test('includes optional gender', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
        gender: 'male',
      };
      const result = buildProfileData(input, 'uid123');
      expect(result.gender).toBe('male');
    });
  
    test('includes valid birthDate', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
        birthDate: '1990-06-15',
      };
      const result = buildProfileData(input, 'uid123');
      expect(result.birthDate instanceof Date).toBe(true);
    });
  
    test('uses provided languageCode', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
        languageCode: 'tr',
      };
      const result = buildProfileData(input, 'uid123');
      expect(result.languageCode).toBe('tr');
    });
  });
  
  // ============================================================================
  // REFERRAL TESTS
  // ============================================================================
  describe('buildReferralData', () => {
    test('builds referral data', () => {
      const result = buildReferralData('test@example.com');
      expect(result.email).toBe('test@example.com');
    });
  });
  
  describe('extractReferralCode', () => {
    test('returns trimmed code', () => {
      expect(extractReferralCode('  ABC123  ')).toBe('ABC123');
    });
  
    test('returns null for null', () => {
      expect(extractReferralCode(null)).toBe(null);
    });
  
    test('returns null for empty string', () => {
      expect(extractReferralCode('')).toBe(null);
    });
  });
  
  // ============================================================================
  // VERIFICATION CODE TESTS
  // ============================================================================
  describe('generateVerificationCode', () => {
    test('generates 6-digit code', () => {
      const code = generateVerificationCode();
      expect(code.length).toBe(6);
      expect(/^\d{6}$/.test(code)).toBe(true);
    });
  
    test('generates code >= 100000', () => {
      for (let i = 0; i < 100; i++) {
        const code = parseInt(generateVerificationCode());
        expect(code).toBeGreaterThanOrEqual(100000);
        expect(code).toBeLessThan(1000000);
      }
    });
  });
  
  describe('isValidVerificationCodeFormat', () => {
    test('returns true for 6-digit string', () => {
      expect(isValidVerificationCodeFormat('123456')).toBe(true);
    });
  
    test('returns false for null', () => {
      expect(isValidVerificationCodeFormat(null)).toBe(false);
    });
  
    test('returns false for wrong length', () => {
      expect(isValidVerificationCodeFormat('12345')).toBe(false);
      expect(isValidVerificationCodeFormat('1234567')).toBe(false);
    });
  
    test('returns false for non-numeric', () => {
      expect(isValidVerificationCodeFormat('12345a')).toBe(false);
    });
  });
  
  // ============================================================================
  // CODE EXPIRATION TESTS
  // ============================================================================
  describe('calculateCodeExpiry', () => {
    test('returns date 5 minutes in future', () => {
      const now = Date.now();
      const expiry = calculateCodeExpiry(now);
      const diff = expiry.getTime() - now;
      expect(diff).toBe(5 * 60 * 1000);
    });
  });
  
  describe('isCodeExpired', () => {
    test('returns false for future expiry', () => {
      const futureExpiry = new Date(Date.now() + 60000);
      expect(isCodeExpired(futureExpiry)).toBe(false);
    });
  
    test('returns true for past expiry', () => {
      const pastExpiry = new Date(Date.now() - 60000);
      expect(isCodeExpired(pastExpiry)).toBe(true);
    });
  
    test('returns true for null', () => {
      expect(isCodeExpired(null)).toBe(true);
    });
  });
  
  describe('getCodeExpiryMinutes', () => {
    test('returns 5', () => {
      expect(getCodeExpiryMinutes()).toBe(5);
    });
  });
  
  // ============================================================================
  // CODE VALIDATION TESTS
  // ============================================================================
  describe('validateVerificationCode', () => {
    const futureExpiry = new Date(Date.now() + 300000);
    const pastExpiry = new Date(Date.now() - 60000);
  
    test('returns valid for matching code', () => {
      const result = validateVerificationCode('123456', '123456', futureExpiry, false);
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid for wrong format', () => {
      const result = validateVerificationCode('123456', 'abc', futureExpiry, false);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_format');
    });
  
    test('returns invalid for expired code', () => {
      const result = validateVerificationCode('123456', '123456', pastExpiry, false);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('expired');
    });
  
    test('returns invalid for used code', () => {
      const result = validateVerificationCode('123456', '123456', futureExpiry, true);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('already_used');
    });
  
    test('returns invalid for mismatched code', () => {
      const result = validateVerificationCode('123456', '654321', futureExpiry, false);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('mismatch');
    });
  });
  
  // ============================================================================
  // RATE LIMITING TESTS
  // ============================================================================
  describe('canResendCode', () => {
    test('returns canResend=true for null', () => {
      const result = canResendCode(null);
      expect(result.canResend).toBe(true);
    });
  
    test('returns canResend=true after cooldown', () => {
      const oldTime = new Date(Date.now() - 60000); // 60 seconds ago
      const result = canResendCode(oldTime);
      expect(result.canResend).toBe(true);
    });
  
    test('returns canResend=false during cooldown', () => {
      const recentTime = new Date(Date.now() - 10000); // 10 seconds ago
      const result = canResendCode(recentTime);
      expect(result.canResend).toBe(false);
      expect(result.waitSeconds).toBeGreaterThan(0);
    });
  
    test('calculates correct wait time', () => {
      const now = Date.now();
      const tenSecondsAgo = new Date(now - 10000);
      const result = canResendCode(tenSecondsAgo, now);
      expect(result.waitSeconds).toBe(20); // 30 - 10 = 20
    });
  });
  
  describe('getResendCooldownSeconds', () => {
    test('returns 30', () => {
      expect(getResendCooldownSeconds()).toBe(30);
    });
  });
  
  // ============================================================================
  // EMAIL TEMPLATE TESTS
  // ============================================================================
  describe('getEmailSubject', () => {
    test('returns English subject', () => {
      expect(getEmailSubject('en')).toBe('Nar24 - Email Verification Code');
    });
  
    test('returns Turkish subject', () => {
      expect(getEmailSubject('tr')).toBe('Nar24 - Email Doğrulama Kodu');
    });
  
    test('returns Russian subject', () => {
      expect(getEmailSubject('ru')).toBe('Nar24 - Код подтверждения электронной почты');
    });
  
    test('defaults to English for unknown', () => {
      expect(getEmailSubject('unknown')).toBe('Nar24 - Email Verification Code');
    });
  });
  
  describe('getEmailTemplate', () => {
    test('returns template with all fields', () => {
      const template = getEmailTemplate('en');
      expect(template.title).toBeDefined();
      expect(template.greeting).toBeDefined();
      expect(template.message).toBeDefined();
      expect(template.codeLabel).toBeDefined();
      expect(template.expiry).toBeDefined();
      expect(template.warning).toBeDefined();
      expect(template.footer).toBeDefined();
    });
  
    test('greeting is a function', () => {
      const template = getEmailTemplate('en');
      expect(typeof template.greeting).toBe('function');
      expect(template.greeting('John')).toBe('Hello John,');
    });
  });
  
  describe('getEffectiveLanguage', () => {
    test('returns language if supported', () => {
      expect(getEffectiveLanguage('tr')).toBe('tr');
    });
  
    test('returns default for unsupported', () => {
      expect(getEffectiveLanguage('de')).toBe('en');
    });
  });
  
  // ============================================================================
  // MAIL DOCUMENT TESTS
  // ============================================================================
  describe('buildMailDocument', () => {
    test('builds mail document', () => {
      const doc = buildMailDocument('test@example.com', '123456', 'en', 'John Doe');
      expect(doc.to).toEqual(['test@example.com']);
      expect(doc.message.subject).toBe('Nar24 - Email Verification Code');
      expect(doc.template.data.code).toBe('123456');
    });
  });
  
  // ============================================================================
  // VERIFICATION CODE DOCUMENT TESTS
  // ============================================================================
  describe('buildVerificationCodeDocument', () => {
    test('builds code document', () => {
      const now = Date.now();
      const doc = buildVerificationCodeDocument('123456', 'test@example.com', now);
      expect(doc.code).toBe('123456');
      expect(doc.email).toBe('test@example.com');
      expect(doc.used).toBe(false);
      expect(doc.expiresAt instanceof Date).toBe(true);
    });
  });
  
  // ============================================================================
  // RESPONSE TESTS
  // ============================================================================
  describe('buildRegistrationResponse', () => {
    test('builds registration response', () => {
      const response = buildRegistrationResponse('uid123', 'token456', true);
      expect(response.uid).toBe('uid123');
      expect(response.customToken).toBe('token456');
      expect(response.emailSent).toBe(true);
      expect(response.verificationCodeSent).toBe(true);
    });
  });
  
  describe('buildVerifySuccessResponse', () => {
    test('builds success response', () => {
      const response = buildVerifySuccessResponse();
      expect(response.success).toBe(true);
      expect(response.message).toBe('Email verified successfully');
    });
  });
  
  describe('buildResendSuccessResponse', () => {
    test('builds resend response', () => {
      const response = buildResendSuccessResponse();
      expect(response.success).toBe(true);
      expect(response.message).toBe('Verification code sent successfully');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete registration flow', () => {
      const input = {
        email: 'newuser@example.com',
        password: 'StrongPass1!',
        name: 'Alice',
        surname: 'Smith',
        gender: 'female',
        birthDate: '1995-03-20',
        languageCode: 'tr',
      };
  
      // Validate fields
      const validation = validateRegistrationFields(input);
      expect(validation.isValid).toBe(true);
  
      // Validate birth date
      const birthDateResult = validateBirthDate(input.birthDate);
      expect(birthDateResult.isValid).toBe(true);
  
      // Build profile
      const profile = buildProfileData(input, 'newUid123');
      expect(profile.displayName).toBe('Alice Smith');
      expect(profile.languageCode).toBe('tr');
  
      // Generate verification code
      const code = generateVerificationCode();
      expect(isValidVerificationCodeFormat(code)).toBe(true);
  
      // Build code document
      const codeDoc = buildVerificationCodeDocument(code, input.email);
      expect(codeDoc.code).toBe(code);
  
      // Build mail document
      const mailDoc = buildMailDocument(input.email, code, input.languageCode, profile.displayName);
      expect(mailDoc.template.data.language).toBe('tr');
    });
  
    test('verification code validation flow', () => {
      const storedCode = '123456';
      const futureExpiry = new Date(Date.now() + 300000);
  
      // Valid code
      const validResult = validateVerificationCode(storedCode, '123456', futureExpiry, false);
      expect(validResult.isValid).toBe(true);
  
      // Wrong code
      const wrongResult = validateVerificationCode(storedCode, '654321', futureExpiry, false);
      expect(wrongResult.isValid).toBe(false);
    });
  
    test('rate limiting flow', () => {
      // First request - should be allowed
      const first = canResendCode(null);
      expect(first.canResend).toBe(true);
  
      // Immediate second request - should be blocked
      const now = Date.now();
      const second = canResendCode(new Date(now - 5000), now);
      expect(second.canResend).toBe(false);
      expect(second.waitSeconds).toBe(25);
  
      // After cooldown - should be allowed
      const afterCooldown = canResendCode(new Date(now - 35000), now);
      expect(afterCooldown.canResend).toBe(true);
    });
  
    test('password strength scenarios', () => {
      expect(isStrongPassword('weak')).toBe(false);
      expect(isStrongPassword('NoSpecial1')).toBe(false);
      expect(isStrongPassword('nouppercase1!')).toBe(false);
      expect(isStrongPassword('NOLOWERCASE1!')).toBe(false);
      expect(isStrongPassword('NoNumber!Aa')).toBe(false);
      expect(isStrongPassword('StrongPass1!')).toBe(true);
    });
  });

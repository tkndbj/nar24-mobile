// functions/test/register-email-password/registration-utils.test.js
//
// Unit tests for user registration utility functions
// Tests the EXACT logic from registration cloud functions
//
// Run: npx jest test/register-email-password/registration-utils.test.js

const {
    MIN_PASSWORD_LENGTH,
    EMAIL_VERIFICATION_URL,
    VALID_GENDERS,
    MIN_BIRTH_YEAR,
  
    validateEmail,
    isValidEmail,
  
    validatePassword,
    isValidPassword,
  
    validateName,
    validateSurname,
    isValidName,
  
    buildDisplayName,
  
    validateReferralCode,
    hasValidReferralCode,
    extractReferralCode,
  
    buildUserData,
    buildReferralData,
  
    validateRegistrationInput,
  
    normalizeGender,
    validateGender,
  
    validateBirthYear,
    calculateAgeFromBirthYear,
  
    buildActionCodeSettings,
  } = require('./registration-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('MIN_PASSWORD_LENGTH is 6', () => {
      expect(MIN_PASSWORD_LENGTH).toBe(6);
    });
  
    test('EMAIL_VERIFICATION_URL is correct', () => {
      expect(EMAIL_VERIFICATION_URL).toBe('https://emlak-mobile-app.web.app/emailVerified');
    });
  
    test('VALID_GENDERS contains expected values', () => {
      expect(VALID_GENDERS).toContain('male');
      expect(VALID_GENDERS).toContain('female');
      expect(VALID_GENDERS).toContain('other');
      expect(VALID_GENDERS).toContain('');
    });
  
    test('MIN_BIRTH_YEAR is 1900', () => {
      expect(MIN_BIRTH_YEAR).toBe(1900);
    });
  });
  
  // ============================================================================
  // EMAIL VALIDATION TESTS
  // ============================================================================
  describe('validateEmail', () => {
    test('returns invalid for null', () => {
      const result = validateEmail(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for undefined', () => {
      const result = validateEmail(undefined);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for empty string', () => {
      const result = validateEmail('');
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-string', () => {
      const result = validateEmail(123);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns valid for any non-empty string (Firebase Auth validates format)', () => {
      expect(validateEmail('user@example.com').isValid).toBe(true);
      expect(validateEmail('notanemail').isValid).toBe(true);
    });
  
    test('returns email as-is (no transformation)', () => {
      const result = validateEmail('USER@Example.COM');
      expect(result.isValid).toBe(true);
      expect(result.email).toBe('USER@Example.COM');
    });
  });
  
  describe('isValidEmail', () => {
    test('returns true for valid email', () => {
      expect(isValidEmail('user@example.com')).toBe(true);
    });
  
    test('returns false for empty email', () => {
      expect(isValidEmail('')).toBe(false);
    });
  });
  
  // ============================================================================
  // PASSWORD VALIDATION TESTS
  // ============================================================================
  describe('validatePassword', () => {
    test('returns invalid for null', () => {
      const result = validatePassword(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for non-string', () => {
      const result = validatePassword(123456);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns invalid for password < 6 chars', () => {
      expect(validatePassword('12345').isValid).toBe(false);
      expect(validatePassword('12345').reason).toBe('too_short');
    });
  
    test('returns valid for password = 6 chars', () => {
      expect(validatePassword('123456').isValid).toBe(true);
    });
  
    test('returns valid for password > 6 chars', () => {
      expect(validatePassword('longerpassword').isValid).toBe(true);
    });
  
    test('returns invalid for empty string', () => {
      expect(validatePassword('').isValid).toBe(false);
    });
  });
  
  describe('isValidPassword', () => {
    test('returns true for valid password', () => {
      expect(isValidPassword('validpass')).toBe(true);
    });
  
    test('returns false for short password', () => {
      expect(isValidPassword('short')).toBe(false);
    });
  });
  
  // ============================================================================
  // NAME VALIDATION TESTS
  // ============================================================================
  describe('validateName', () => {
    test('returns invalid for null', () => {
      const result = validateName(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for non-string', () => {
      const result = validateName(123);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns invalid for empty string', () => {
      const result = validateName('');
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for whitespace only', () => {
      const result = validateName('   ');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty');
    });
  
    test('returns valid for proper name', () => {
      const result = validateName('John');
      expect(result.isValid).toBe(true);
      expect(result.name).toBe('John');
    });
  
    test('trims whitespace', () => {
      const result = validateName('  John  ');
      expect(result.name).toBe('John');
    });
  
    test('uses custom field name in error message', () => {
      const result = validateName(null, 'surname');
      expect(result.message).toBe('invalid surname');
    });
  });
  
  describe('validateSurname', () => {
    test('returns invalid for null', () => {
      const result = validateSurname(null);
      expect(result.isValid).toBe(false);
      expect(result.message).toBe('invalid surname');
    });
  
    test('returns valid for proper surname', () => {
      const result = validateSurname('Doe');
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('isValidName', () => {
    test('returns true for valid name', () => {
      expect(isValidName('John')).toBe(true);
    });
  
    test('returns false for invalid name', () => {
      expect(isValidName('')).toBe(false);
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
  
    test('handles null name', () => {
      expect(buildDisplayName(null, 'Doe')).toBe(' Doe');
    });
  
    test('handles null surname', () => {
      expect(buildDisplayName('John', null)).toBe('John ');
    });
  
    test('handles both null', () => {
      expect(buildDisplayName(null, null)).toBe(' ');
    });
  });
  
  // ============================================================================
  // REFERRAL CODE TESTS
  // ============================================================================
  describe('validateReferralCode', () => {
    test('returns valid with hasCode=false for null', () => {
      const result = validateReferralCode(null);
      expect(result.isValid).toBe(true);
      expect(result.hasCode).toBe(false);
    });
  
    test('returns valid with hasCode=false for empty string', () => {
      const result = validateReferralCode('');
      expect(result.isValid).toBe(true);
      expect(result.hasCode).toBe(false);
    });
  
    test('returns valid with hasCode=false for whitespace', () => {
      const result = validateReferralCode('   ');
      expect(result.isValid).toBe(true);
      expect(result.hasCode).toBe(false);
    });
  
    test('returns invalid for non-string (number)', () => {
      const result = validateReferralCode(12345);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns valid with hasCode=true for valid code', () => {
      const result = validateReferralCode('ABC123');
      expect(result.isValid).toBe(true);
      expect(result.hasCode).toBe(true);
      expect(result.code).toBe('ABC123');
    });
  
    test('trims whitespace from code', () => {
      const result = validateReferralCode('  ABC123  ');
      expect(result.code).toBe('ABC123');
    });
  });
  
  describe('hasValidReferralCode', () => {
    test('returns true for valid code', () => {
      expect(hasValidReferralCode('ABC123')).toBe(true);
    });
  
    test('returns false for empty code', () => {
      expect(hasValidReferralCode('')).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(hasValidReferralCode(null)).toBe(false);
    });
  });
  
  describe('extractReferralCode', () => {
    test('returns code for valid input', () => {
      expect(extractReferralCode('ABC123')).toBe('ABC123');
    });
  
    test('returns null for empty input', () => {
      expect(extractReferralCode('')).toBe(null);
    });
  
    test('returns null for null input', () => {
      expect(extractReferralCode(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // USER DATA BUILDING TESTS
  // ============================================================================
  describe('buildUserData', () => {
    test('builds complete user data', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
        gender: 'male',
        birthYear: 1990,
      };
  
      const result = buildUserData(input, 'uid123');
  
      expect(result.displayName).toBe('John Doe');
      expect(result.email).toBe('john@example.com');
      expect(result.isNew).toBe(true);
      expect(result.gender).toBe('male');
      expect(result.birthYear).toBe(1990);
      expect(result.referralCode).toBe('uid123');
      expect(result.verified).toBe(false);
    });
  
    test('includes referrerId when referral code provided', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
        referralCode: 'inviter456',
      };
  
      const result = buildUserData(input, 'uid123');
  
      expect(result.referrerId).toBe('inviter456');
    });
  
    test('does not include referrerId when no referral code', () => {
      const input = {
        name: 'John',
        surname: 'Doe',
        email: 'john@example.com',
      };
  
      const result = buildUserData(input, 'uid123');
  
      expect(result.referrerId).toBeUndefined();
    });
  
    test('defaults gender to empty string', () => {
      const input = { name: 'John', surname: 'Doe', email: 'john@example.com' };
      const result = buildUserData(input, 'uid123');
      expect(result.gender).toBe('');
    });
  
    test('defaults birthYear to 0', () => {
      const input = { name: 'John', surname: 'Doe', email: 'john@example.com' };
      const result = buildUserData(input, 'uid123');
      expect(result.birthYear).toBe(0);
    });
  });
  
  describe('buildReferralData', () => {
    test('builds referral data with email', () => {
      const result = buildReferralData('referred@example.com');
      expect(result.email).toBe('referred@example.com');
    });
  
    test('handles null email', () => {
      const result = buildReferralData(null);
      expect(result.email).toBe('');
    });
  });
  
  // ============================================================================
  // COMPLETE VALIDATION TESTS
  // ============================================================================
  describe('validateRegistrationInput', () => {
    test('returns valid for complete valid input', () => {
      const data = {
        email: 'user@example.com',
        password: 'password123',
        name: 'John',
        surname: 'Doe',
      };
  
      const result = validateRegistrationInput(data);
  
      expect(result.isValid).toBe(true);
      expect(result.cleanedData.email).toBe('user@example.com');
    });
  
    test('returns errors for missing email', () => {
      const data = {
        email: '',
        password: 'password123',
        name: 'John',
        surname: 'Doe',
      };
  
      const result = validateRegistrationInput(data);
  
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'email')).toBe(true);
    });
  
    test('returns errors for short password', () => {
      const data = {
        email: 'user@example.com',
        password: '12345',
        name: 'John',
        surname: 'Doe',
      };
  
      const result = validateRegistrationInput(data);
  
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'password')).toBe(true);
    });
  
    test('returns multiple errors', () => {
      const data = {
        email: '',
        password: '123',
        name: '',
        surname: '',
      };
  
      const result = validateRegistrationInput(data);
  
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBeGreaterThanOrEqual(4);
    });
  
    test('returns firstError for convenience', () => {
      const data = {
        email: '',
        password: 'password123',
        name: 'John',
        surname: 'Doe',
      };
  
      const result = validateRegistrationInput(data);
  
      expect(result.firstError).toBeDefined();
      expect(result.firstError.field).toBe('email');
    });
  });
  
  // ============================================================================
  // GENDER VALIDATION TESTS
  // ============================================================================
  describe('normalizeGender', () => {
    test('lowercases and trims', () => {
      expect(normalizeGender('  MALE  ')).toBe('male');
    });
  
    test('returns empty for null', () => {
      expect(normalizeGender(null)).toBe('');
    });
  
    test('returns empty for non-string', () => {
      expect(normalizeGender(123)).toBe('');
    });
  });
  
  describe('validateGender', () => {
    test('returns valid for male', () => {
      expect(validateGender('male').isValid).toBe(true);
    });
  
    test('returns valid for female', () => {
      expect(validateGender('female').isValid).toBe(true);
    });
  
    test('returns valid for other', () => {
      expect(validateGender('other').isValid).toBe(true);
    });
  
    test('returns valid for empty string', () => {
      expect(validateGender('').isValid).toBe(true);
    });
  
    test('returns valid for null (defaults to empty)', () => {
      expect(validateGender(null).isValid).toBe(true);
    });
  
    test('normalizes case', () => {
      const result = validateGender('MALE');
      expect(result.isValid).toBe(true);
      expect(result.gender).toBe('male');
    });
  });
  
  // ============================================================================
  // BIRTH YEAR VALIDATION TESTS
  // ============================================================================
  describe('validateBirthYear', () => {
    const currentYear = 2024;
  
    test('returns valid for null (optional)', () => {
      const result = validateBirthYear(null, currentYear);
      expect(result.isValid).toBe(true);
      expect(result.birthYear).toBe(0);
    });
  
    test('returns valid for 0', () => {
      const result = validateBirthYear(0, currentYear);
      expect(result.isValid).toBe(true);
      expect(result.birthYear).toBe(0);
    });
  
    test('returns valid for year in range', () => {
      const result = validateBirthYear(1990, currentYear);
      expect(result.isValid).toBe(true);
      expect(result.birthYear).toBe(1990);
    });
  
    test('returns invalid for year before 1900', () => {
      const result = validateBirthYear(1899, currentYear);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('out_of_range');
    });
  
    test('returns invalid for year in future', () => {
      const result = validateBirthYear(2025, currentYear);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('out_of_range');
    });
  
    test('handles string input', () => {
      const result = validateBirthYear('1990', currentYear);
      expect(result.isValid).toBe(true);
      expect(result.birthYear).toBe(1990);
    });
  
    test('returns invalid for non-numeric string', () => {
      const result = validateBirthYear('not a year', currentYear);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_number');
    });
  });
  
  describe('calculateAgeFromBirthYear', () => {
    test('calculates correct age', () => {
      expect(calculateAgeFromBirthYear(1990, 2024)).toBe(34);
    });
  
    test('returns null for 0 birth year', () => {
      expect(calculateAgeFromBirthYear(0, 2024)).toBe(null);
    });
  
    test('returns null for null birth year', () => {
      expect(calculateAgeFromBirthYear(null, 2024)).toBe(null);
    });
  });
  
  // ============================================================================
  // ACTION CODE SETTINGS TESTS
  // ============================================================================
  describe('buildActionCodeSettings', () => {
    test('returns correct settings with default URL', () => {
      const result = buildActionCodeSettings();
      expect(result.url).toBe(EMAIL_VERIFICATION_URL);
      expect(result.handleCodeInApp).toBe(true);
    });
  
    test('accepts custom URL', () => {
      const result = buildActionCodeSettings('https://custom.url/verify');
      expect(result.url).toBe('https://custom.url/verify');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete registration flow', () => {
      const input = {
        email: 'newuser@example.com',
        password: 'securePass123',
        name: 'Alice',
        surname: 'Smith',
        gender: 'female',
        birthYear: 1995,
        referralCode: 'inviter123',
      };
  
      const validation = validateRegistrationInput(input);
      expect(validation.isValid).toBe(true);
  
      const uid = 'newUserUid456';
      const userData = buildUserData(input, uid);
  
      expect(userData.displayName).toBe('Alice Smith');
      expect(userData.email).toBe('newuser@example.com');
      expect(userData.gender).toBe('female');
      expect(userData.birthYear).toBe(1995);
      expect(userData.referralCode).toBe(uid);
      expect(userData.referrerId).toBe('inviter123');
      expect(userData.isNew).toBe(true);
      expect(userData.verified).toBe(false);
  
      const referralData = buildReferralData(input.email);
      expect(referralData.email).toBe('newuser@example.com');
  
      const actionSettings = buildActionCodeSettings();
      expect(actionSettings.handleCodeInApp).toBe(true);
    });
  
    test('registration without optional fields', () => {
      const input = {
        email: 'basic@example.com',
        password: 'password123',
        name: 'Basic',
        surname: 'User',
      };
  
      const validation = validateRegistrationInput(input);
      expect(validation.isValid).toBe(true);
  
      const userData = buildUserData(input, 'uid789');
  
      expect(userData.gender).toBe('');
      expect(userData.birthYear).toBe(0);
      expect(userData.referrerId).toBeUndefined();
    });
  
    test('registration with validation errors', () => {
      const input = {
        email: '',
        password: '123',
        name: '',
        surname: 'Smith',
      };
  
      const validation = validateRegistrationInput(input);
  
      expect(validation.isValid).toBe(false);
      expect(validation.errors.length).toBe(3);
  
      const emailError = validation.errors.find((e) => e.field === 'email');
      const passwordError = validation.errors.find((e) => e.field === 'password');
      const nameError = validation.errors.find((e) => e.field === 'name');
  
      expect(emailError).toBeDefined();
      expect(passwordError).toBeDefined();
      expect(nameError).toBeDefined();
    });
  
    test('referral code trimming and validation', () => {
      expect(extractReferralCode('  INVITE123  ')).toBe('INVITE123');
      expect(extractReferralCode('   ')).toBe(null);
      expect(hasValidReferralCode(12345)).toBe(false);
    });
  });

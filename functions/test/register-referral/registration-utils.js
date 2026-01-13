// functions/test/register-email-password/registration-utils.js
//
// EXTRACTED PURE LOGIC from user registration cloud functions
// These functions are EXACT COPIES of logic from the registration functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source registration functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const MIN_PASSWORD_LENGTH = 6;

const EMAIL_VERIFICATION_URL = 'https://emlak-mobile-app.web.app/emailVerified';

// ============================================================================
// EMAIL VALIDATION
// ============================================================================

function validateEmail(email) {
  if (!email) {
    return {
      isValid: false,
      reason: 'missing',
      message: 'invalid email',
    };
  }

  if (typeof email !== 'string') {
    return {
      isValid: false,
      reason: 'not_string',
      message: 'invalid email',
    };
  }

  // Production code doesn't validate format - Firebase Auth handles that
  return {
    isValid: true,
    email: email,
  };
}

function isValidEmail(email) {
  return validateEmail(email).isValid;
}

// ============================================================================
// PASSWORD VALIDATION
// ============================================================================

function validatePassword(password) {
  if (!password) {
    return {
      isValid: false,
      reason: 'missing',
      message: 'invalid password min 6 chars',
    };
  }

  if (typeof password !== 'string') {
    return {
      isValid: false,
      reason: 'not_string',
      message: 'invalid password min 6 chars',
    };
  }

  if (password.length < MIN_PASSWORD_LENGTH) {
    return {
      isValid: false,
      reason: 'too_short',
      message: 'invalid password min 6 chars',
    };
  }

  return {
    isValid: true,
  };
}

function isValidPassword(password) {
  return validatePassword(password).isValid;
}

// ============================================================================
// NAME VALIDATION
// ============================================================================

function validateName(name, fieldName = 'name') {
  if (!name) {
    return {
      isValid: false,
      reason: 'missing',
      message: `invalid ${fieldName}`,
    };
  }

  if (typeof name !== 'string') {
    return {
      isValid: false,
      reason: 'not_string',
      message: `invalid ${fieldName}`,
    };
  }

  const trimmed = name.trim();
  if (trimmed.length === 0) {
    return {
      isValid: false,
      reason: 'empty',
      message: `invalid ${fieldName}`,
    };
  }

  return {
    isValid: true,
    name: trimmed,
  };
}

function validateSurname(surname) {
  return validateName(surname, 'surname');
}

function isValidName(name) {
  return validateName(name).isValid;
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
// REFERRAL CODE VALIDATION
// ============================================================================

function validateReferralCode(referralCode) {
  if (!referralCode) {
    return {
      isValid: true,
      hasCode: false,
      code: null,
    };
  }

  if (typeof referralCode !== 'string') {
    return {
      isValid: false,
      reason: 'not_string',
      message: 'invalid referral code',
    };
  }

  const trimmed = referralCode.trim();
  if (trimmed === '') {
    return {
      isValid: true,
      hasCode: false,
      code: null,
    };
  }

  return {
    isValid: true,
    hasCode: true,
    code: trimmed,
  };
}

function hasValidReferralCode(referralCode) {
  const result = validateReferralCode(referralCode);
  return result.isValid && result.hasCode;
}

function extractReferralCode(referralCode) {
  const result = validateReferralCode(referralCode);
  return result.hasCode ? result.code : null;
}

// ============================================================================
// USER DATA BUILDING
// ============================================================================

function buildUserData(input, uid) {
  const { name, surname, email, gender, birthYear, referralCode } = input;

  const userData = {
    displayName: buildDisplayName(name, surname),
    email: email || '',
    isNew: true,
    gender: gender || '',
    birthYear: birthYear || 0,
    referralCode: uid,
    verified: false,
  };

  const cleanReferralCode = extractReferralCode(referralCode);
  if (cleanReferralCode) {
    userData.referrerId = cleanReferralCode;
  }

  return userData;
}

function buildReferralData(email) {
  return {
    email: email || '',
  };
}

// ============================================================================
// COMPLETE REGISTRATION VALIDATION
// ============================================================================

function validateRegistrationInput(data) {
  const errors = [];

  const emailResult = validateEmail(data.email);
  if (!emailResult.isValid) {
    errors.push({ field: 'email', message: emailResult.message });
  }

  const passwordResult = validatePassword(data.password);
  if (!passwordResult.isValid) {
    errors.push({ field: 'password', message: passwordResult.message });
  }

  const nameResult = validateName(data.name);
  if (!nameResult.isValid) {
    errors.push({ field: 'name', message: nameResult.message });
  }

  const surnameResult = validateSurname(data.surname);
  if (!surnameResult.isValid) {
    errors.push({ field: 'surname', message: surnameResult.message });
  }

  const referralResult = validateReferralCode(data.referralCode);
  if (!referralResult.isValid) {
    errors.push({ field: 'referralCode', message: referralResult.message });
  }

  if (errors.length > 0) {
    return {
      isValid: false,
      errors,
      firstError: errors[0],
    };
  }

  return {
    isValid: true,
    cleanedData: {
      email: emailResult.email,
      name: nameResult.name,
      surname: surnameResult.name,
      referralCode: referralResult.code,
      gender: data.gender || '',
      birthYear: data.birthYear || 0,
    },
  };
}

// ============================================================================
// GENDER VALIDATION
// ============================================================================

const VALID_GENDERS = ['male', 'female', 'other', ''];

function normalizeGender(gender) {
  if (!gender || typeof gender !== 'string') {
    return '';
  }
  return gender.trim().toLowerCase();
}

function validateGender(gender) {
  const normalized = normalizeGender(gender);
  
  if (normalized === '') {
    return { isValid: true, gender: '' };
  }

  if (VALID_GENDERS.includes(normalized)) {
    return { isValid: true, gender: normalized };
  }

  return {
    isValid: false,
    reason: 'invalid_value',
    message: 'invalid gender',
  };
}

// ============================================================================
// BIRTH YEAR VALIDATION
// ============================================================================

const MIN_BIRTH_YEAR = 1900;

function validateBirthYear(birthYear, currentYear = new Date().getFullYear()) {
  if (!birthYear && birthYear !== 0) {
    return { isValid: true, birthYear: 0 };
  }

  const year = typeof birthYear === 'string' ? parseInt(birthYear, 10) : birthYear;

  if (typeof year !== 'number' || isNaN(year)) {
    return {
      isValid: false,
      reason: 'not_number',
      message: 'invalid birth year',
    };
  }

  if (year === 0) {
    return { isValid: true, birthYear: 0 };
  }

  if (year < MIN_BIRTH_YEAR || year > currentYear) {
    return {
      isValid: false,
      reason: 'out_of_range',
      message: 'invalid birth year',
    };
  }

  return { isValid: true, birthYear: year };
}

function calculateAgeFromBirthYear(birthYear, currentYear = new Date().getFullYear()) {
  if (!birthYear || birthYear === 0) {
    return null;
  }
  return currentYear - birthYear;
}

// ============================================================================
// ACTION CODE SETTINGS
// ============================================================================

function buildActionCodeSettings(url = EMAIL_VERIFICATION_URL) {
  return {
    url,
    handleCodeInApp: true,
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
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
};

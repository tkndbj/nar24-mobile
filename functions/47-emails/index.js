import {onCall, HttpsError} from 'firebase-functions/v2/https';                                                                                                                                                                                           
import admin from 'firebase-admin';
import {Storage} from '@google-cloud/storage';
const storage = new Storage();

export const registerWithEmailPassword = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const {
        email,
        password,
        name,
        surname,
        gender,
        birthDate,
        referralCode,
        languageCode = 'en', // Default to English if not provided
      } = request.data;
  
      // 1) Basic validation
      if (
        !email || typeof email !== 'string' ||
        !password || typeof password !== 'string' ||
        !name || typeof name !== 'string' ||
        !surname || typeof surname !== 'string'
      ) {
        throw new HttpsError(
          'invalid-argument',
          'email (string), password (min 6 chars), name & surname are required',
        );
      }
  
      if (password.length < 8) {
        throw new HttpsError(
          'invalid-argument',
          'Password must be at least 8 characters long',
        );
      }
  
      if (!/[A-Z]/.test(password)) {
        throw new HttpsError(
          'invalid-argument',
          'Password must contain at least one uppercase letter',
        );
      }
  
      if (!/[a-z]/.test(password)) {
        throw new HttpsError(
          'invalid-argument',
          'Password must contain at least one lowercase letter',
        );
      }
  
      if (!/[0-9]/.test(password)) {
        throw new HttpsError(
          'invalid-argument',
          'Password must contain at least one number',
        );
      }
  
      if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
        throw new HttpsError(
          'invalid-argument',
          'Password must contain at least one special character',
        );
      }
  
      let userRecord;
      try {
        // 2) Create the Auth user
        userRecord = await admin.auth().createUser({
          email,
          password,
          displayName: `${name.trim()} ${surname.trim()}`,
          emailVerified: false, // Explicitly set to false initially
        });
      } catch (err) {
        throw new HttpsError('internal', 'Auth.createUser failed: ' + err.message);
      }
  
      const uid = userRecord.uid;
      const now = admin.firestore.FieldValue.serverTimestamp();
  
      // 3) Build the Firestore profile
      const profileData = {
        displayName: `${name.trim()} ${surname.trim()}`,
        email,
        isNew: true,
        isVerified: false,
        referralCode: uid,
        createdAt: now,
        languageCode, // Store the language preference
      };
      if (gender) profileData.gender = gender;
      if (birthDate) {
        const d = new Date(birthDate);
        if (!isNaN(d.getTime())) {
          profileData.birthDate = admin.firestore.Timestamp.fromDate(d);
        } else {
          throw new HttpsError(
            'invalid-argument',
            `birthDate must be a valid ISO string, got "${birthDate}"`,
          );
        }
      }
  
      try {
        await admin.firestore()
          .collection('users')
          .doc(uid)
          .set(profileData, {merge: true});
  
        // 4) If a referralCode was provided, record it
        if (referralCode) {
          await admin.firestore()
            .collection('users')
            .doc(referralCode.trim())
            .collection('referral')
            .doc(uid)
            .set({
              email,
              registeredAt: now,
            });
        }
      } catch (err) {
        await admin.auth().deleteUser(uid).catch(() => {});
        throw new HttpsError('internal', 'Firestore write failed: ' + err.message);
      }
  
      // 5) Generate verification code and send email via SendGrid
      let emailSent = false;
      let verificationCode = '';
  
      try {
        // Generate 6-digit verification code
        verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
  
        // Store verification code in Firestore with expiration
        await admin.firestore()
          .collection('emailVerificationCodes')
          .doc(uid)
          .set({
            code: verificationCode,
            email,
            createdAt: now,
            expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)), // 5 minutes
            used: false,
          });
  
        // Send verification email via SendGrid using mail collection
        await sendVerificationEmail(email, verificationCode, languageCode, `${name.trim()} ${surname.trim()}`);
        emailSent = true;
  
        console.log(`Email verification sent to ${email} (user ${uid}) in ${languageCode}`);
      } catch (err) {
        console.warn('Could not send email verification:', err);
        // Don't throw error - continue with registration
      }
  
      // 6) Mint a Custom Token
      let customToken;
      try {
        customToken = await admin.auth().createCustomToken(uid);
      } catch (err) {
        throw new HttpsError('internal', 'Custom token creation failed: ' + err.message);
      }
  
      return {
        uid,
        customToken,
        emailSent,
        verificationCodeSent: emailSent, // Indicate if verification code was sent
      };
    },
  );
  
  // Helper function to send verification email via SendGrid mail collection
  async function sendVerificationEmail(email, code, languageCode, displayName) {
    const subjects = {
      en: 'Nar24 - Email Verification Code',
      tr: 'Nar24 - Email Doğrulama Kodu',
      ru: 'Nar24 - Код подтверждения электронной почты',
    };
  
    const codeDigits = code.split('');
  
    // Get logo URL from Storage
    let logoUrl = '';
    try {
      const bucket = admin.storage().bucket();
      const logoFile = bucket.file('assets/naricon.png');
      const [exists] = await logoFile.exists();
      if (exists) {
        const [url] = await logoFile.getSignedUrl({
          action: 'read',
          expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
        });
        logoUrl = url;
      }
    } catch (err) {
      console.warn('Could not get logo URL:', err.message);
    }
  
    const getEmailHtml = (lang, codeDigits, name) => {
      const templates = {
        en: {
          greeting: `Hello ${name},`,
          message: 'Thank you for signing up with Nar24. Please enter the verification code below to complete your registration.',
          codeLabel: 'VERIFICATION CODE',
          expiry: 'This code expires in 5 minutes.',
          warning: 'If you did not create an account with Nar24, please ignore this email.',
          rights: 'All rights reserved.',
        },
        tr: {
          greeting: `Merhaba ${name},`,
          message: 'Nar24\'e kaydolduğunuz için teşekkür ederiz. Kaydınızı tamamlamak için aşağıdaki doğrulama kodunu girin.',
          codeLabel: 'DOĞRULAMA KODU',
          expiry: 'Bu kod 5 dakika içinde sona erer.',
          warning: 'Nar24\'te bir hesap oluşturmadıysanız, lütfen bu e-postayı görmezden gelin.',
          rights: 'Tüm hakları saklıdır.',
        },
        ru: {
          greeting: `Здравствуйте, ${name}!`,
          message: 'Благодарим за регистрацию в Nar24. Введите код подтверждения ниже, чтобы завершить регистрацию.',
          codeLabel: 'КОД ПОДТВЕРЖДЕНИЯ',
          expiry: 'Срок действия кода — 5 минут.',
          warning: 'Если вы не создавали учётную запись в Nar24, проигнорируйте это письмо.',
          rights: 'Все права защищены.',
        },
      };
  
      const t = templates[lang] || templates.en;
  
      const digitBoxes = codeDigits.map((digit) => `
                <td style="padding:0 4px;">
                  <table cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                    <tr>
                      <td style="width:44px;height:56px;background-color:#f9fafb;border:2px solid #e5e7eb;border-radius:8px;text-align:center;vertical-align:middle;font-family:Arial,Helvetica,sans-serif;font-size:28px;font-weight:bold;color:#1a1a1a;">
                        ${digit}
                      </td>
                    </tr>
                  </table>
                </td>
      `).join('');
  
      return `
  <!DOCTYPE html>
  <html lang="${lang}">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <!--[if mso]>
    <noscript>
      <xml>
        <o:OfficeDocumentSettings>
          <o:PixelsPerInch>96</o:PixelsPerInch>
        </o:OfficeDocumentSettings>
      </xml>
    </noscript>
    <![endif]-->
  </head>
  <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
    
    <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
      <tr>
        <td align="center">
          <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
            
            <!-- Logo -->
            <tr>
              <td style="padding:32px 40px 24px 40px;text-align:center;">
                ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
              </td>
            </tr>
            
            <!-- Top Gradient Line -->
            <tr>
              <td style="padding:0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Greeting -->
            <tr>
              <td style="padding:32px 40px 0 40px;">
                <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${t.greeting}</p>
                <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${t.message}</p>
              </td>
            </tr>
            
            <!-- Code Label -->
            <tr>
              <td style="padding:28px 40px 12px 40px;text-align:center;">
                <p style="margin:0;font-size:11px;font-weight:600;color:#9ca3af;letter-spacing:1.5px;">${t.codeLabel}</p>
              </td>
            </tr>
            
            <!-- Verification Code Digits -->
            <tr>
              <td style="padding:0 40px;text-align:center;">
                <table cellpadding="0" cellspacing="0" border="0" align="center">
                  <tr>
                    ${digitBoxes}
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Fallback Plain Text Code -->
            <tr>
              <td style="padding:12px 40px 0 40px;text-align:center;">
                <p style="margin:0;font-size:13px;color:#c0c0c0;">Code: <strong style="color:#9ca3af;letter-spacing:2px;">${codeDigits.join('')}</strong></p>
              </td>
            </tr>
            
            <!-- Expiry Notice -->
            <tr>
              <td style="padding:24px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td style="background-color:#f9fafb;border-radius:8px;padding:14px 16px;text-align:center;">
                      <p style="margin:0;font-size:13px;color:#6b7280;">${t.expiry}</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Warning -->
            <tr>
              <td style="padding:20px 40px 0 40px;">
                <p style="margin:0;font-size:13px;color:#c0c0c0;line-height:20px;">${t.warning}</p>
              </td>
            </tr>
            
            <!-- Bottom Gradient Line -->
            <tr>
              <td style="padding:36px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Footer -->
            <tr>
              <td style="padding:20px 40px 32px 40px;text-align:center;">
                <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${t.rights}</p>
              </td>
            </tr>
            
          </table>
        </td>
      </tr>
    </table>
    
  </body>
  </html>
      `;
    };
  
    const mailDoc = {
      to: [email],
      message: {
        subject: subjects[languageCode] || subjects.en,
        html: getEmailHtml(languageCode, codeDigits, displayName),
        text: getPlainTextEmail(languageCode, code, displayName),
      },
    };
  
    await admin.firestore().collection('mail').add(mailDoc);
  }
  
  function getPlainTextEmail(lang, code, name) {
    const templates = {
      en: {
        greeting: `Hello ${name},`,
        message: 'Thank you for signing up with Nar24. Your verification code:',
        expiry: 'This code expires in 5 minutes.',
        warning: 'If you did not create an account with Nar24, please ignore this email.',
      },
      tr: {
        greeting: `Merhaba ${name},`,
        message: 'Nar24\'e kaydolduğunuz için teşekkür ederiz. Doğrulama kodunuz:',
        expiry: 'Bu kod 5 dakika içinde sona erer.',
        warning: 'Nar24\'te bir hesap oluşturmadıysanız, lütfen bu e-postayı görmezden gelin.',
      },
      ru: {
        greeting: `Здравствуйте, ${name}!`,
        message: 'Благодарим за регистрацию в Nar24. Ваш код подтверждения:',
        expiry: 'Срок действия кода — 5 минут.',
        warning: 'Если вы не создавали учётную запись в Nar24, проигнорируйте это письмо.',
      },
    };
  
    const t = templates[lang] || templates.en;
  
    return `
  ${t.greeting}
  
  ${t.message}
  
  ${code}
  
  ${t.expiry}
  
  ${t.warning}
  
  ---
  © 2026 Nar24
    `.trim();
  }
  
  
  export const verifyEmailCode = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const {code} = request.data;
      const context = request.auth;
  
      // Check if user is authenticated
      if (!context || !context.uid) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }
  
      const uid = context.uid;
  
        // Rate limit: max 10 attempts per 15 minutes per user 
    const rateLimitRef = admin.firestore().collection('_rate_limits').doc(`email_verify_${uid}`);
    const windowMs = 15 * 60 * 1000;
    const maxAttempts = 10;
  
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(rateLimitRef);
      const now = Date.now();
  
      if (snap.exists) {
        const data = snap.data();
        const windowStart = data.windowStart?.toMillis?.() ?? 0;
        const count = data.count ?? 0;
  
        if (now - windowStart < windowMs) {
          if (count >= maxAttempts) {
            throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
          }
          tx.update(rateLimitRef, { count: count + 1 });
        } else {
          tx.set(rateLimitRef, { count: 1, windowStart: admin.firestore.Timestamp.fromMillis(now), expiresAt: admin.firestore.Timestamp.fromMillis(now + windowMs) });
        }
      } else {
        tx.set(rateLimitRef, { count: 1, windowStart: admin.firestore.Timestamp.fromMillis(now), expiresAt: admin.firestore.Timestamp.fromMillis(now + windowMs) });
      }
    });
  
      if (!code || typeof code !== 'string' || code.length !== 6) {
        throw new HttpsError('invalid-argument', 'Valid 6-digit code is required');
      }
  
      try {
        // Get the verification code document
        const codeDoc = await admin.firestore()
          .collection('emailVerificationCodes')
          .doc(uid)
          .get();
  
        if (!codeDoc.exists) {
          throw new HttpsError('not-found', 'No verification code found for this user');
        }
  
        const codeData = codeDoc.data();
        const now = new Date();
  
        // Check if code has expired
        if (codeData.expiresAt.toDate() < now) {
          throw new HttpsError('deadline-exceeded', 'Verification code has expired');
        }
  
        // Check if code has already been used
        if (codeData.used) {
          throw new HttpsError('failed-precondition', 'Verification code has already been used');
        }
  
        // Check if code matches
        if (codeData.code !== code) {
          throw new HttpsError('invalid-argument', 'Invalid verification code');
        }
  
        // Mark code as used
        await admin.firestore()
          .collection('emailVerificationCodes')
          .doc(uid)
          .update({
            used: true,
            verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
  
        // Update the user's email verification status in Firebase Auth
        await admin.auth().updateUser(uid, {
          emailVerified: true,
        });
  
        // Update user document in Firestore
        await admin.firestore()
          .collection('users')
          .doc(uid)
          .update({
            isVerified: true,
            emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
  
        console.log(`Email verified successfully for user ${uid}`);
  
        return {
          success: true,
          message: 'Email verified successfully',
        };
      } catch (error) {
        console.error('Error verifying email code:', error);
  
        if (error instanceof HttpsError) {
          throw error;
        }
  
        throw new HttpsError('internal', 'Error verifying email code');
      }
    },
  );
  
  // Function to resend verification code
  export const resendEmailVerificationCode = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const context = request.auth;
  
      if (!context || !context.uid) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }
  
      const uid = context.uid;
  
      try {
        // Get user data
        const userDoc = await admin.firestore()
          .collection('users')
          .doc(uid)
          .get();
  
        if (!userDoc.exists) {
          throw new HttpsError('not-found', 'User document not found');
        }
  
        const userData = userDoc.data();
  
        // Check if email is already verified
        if (userData.isVerified) {
          throw new HttpsError('failed-precondition', 'Email is already verified');
        }
  
        // Check rate limiting - allow resend only after 30 seconds
        const existingCodeDoc = await admin.firestore()
          .collection('emailVerificationCodes')
          .doc(uid)
          .get();
  
        if (existingCodeDoc.exists) {
          const existingData = existingCodeDoc.data();
          const timeSinceLastCode = Date.now() - existingData.createdAt.toMillis();
  
          if (timeSinceLastCode < 30000) { // 30 seconds
            const waitTime = Math.ceil((30000 - timeSinceLastCode) / 1000);
            throw new HttpsError('resource-exhausted', `Please wait ${waitTime} seconds before requesting a new code`);
          }
        }
  
        // Generate new verification code
        const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
        const now = admin.firestore.FieldValue.serverTimestamp();
  
        // Store new verification code
        await admin.firestore()
          .collection('emailVerificationCodes')
          .doc(uid)
          .set({
            code: verificationCode,
            email: userData.email,
            createdAt: now,
            expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)), // 5 minutes
            used: false,
          });
  
        // Send verification email
        await sendVerificationEmail(
          userData.email,
          verificationCode,
          userData.languageCode || 'en',
          userData.displayName || 'User',
        );
  
        return {
          success: true,
          message: 'Verification code sent successfully',
        };
      } catch (error) {
        console.error('Error resending verification code:', error);
  
        if (error instanceof HttpsError) {
          throw error;
        }
  
        throw new HttpsError('internal', 'Error resending verification code');
      }
    },
  );
  
  export const sendPasswordResetEmail = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const {email} = request.data;
  
      if (!email) {
        throw new HttpsError('invalid-argument', 'Email is required');
      }
  
      try {
        // Get user's language preference (don't reveal if user exists)
        let languageCode = 'en';
        let displayName = '';
  
        try {
          const userRecord = await admin.auth().getUserByEmail(email.trim().toLowerCase());
          const userDoc = await admin.firestore()
            .collection('users')
            .doc(userRecord.uid)
            .get();
  
          if (userDoc.exists) {
            const userData = userDoc.data();
            languageCode = userData.languageCode || 'en';
            displayName = userData.displayName || '';
          }
        } catch (err) {
          // User not found — return success anyway to not reveal if email exists
          return {success: true};
        }
  
        // Generate password reset link via Admin SDK
        const resetLink = await admin.auth().generatePasswordResetLink(
          email.trim().toLowerCase(),
        );
  
        // Get logo URL from Storage
        let logoUrl = '';
        try {
          const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
          const logoFile = bucket.file('assets/naricon.png');
          const [exists] = await logoFile.exists();
          if (exists) {
            const [url] = await logoFile.getSignedUrl({
              action: 'read',
              expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
            });
            logoUrl = url;
          }
        } catch (err) {
          console.warn('Could not get logo URL:', err.message);
        }
  
        const content = getPasswordResetContent(languageCode);
        const greeting = displayName ? `${content.greeting} ${displayName},` : `${content.greeting},`;
  
        const emailHtml = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!--[if mso]>
    <noscript>
      <xml>
        <o:OfficeDocumentSettings>
          <o:PixelsPerInch>96</o:PixelsPerInch>
        </o:OfficeDocumentSettings>
      </xml>
    </noscript>
    <![endif]-->
  </head>
  <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
    
    <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
      <tr>
        <td align="center">
          <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
            
            <!-- Logo -->
            <tr>
              <td style="padding:32px 40px 24px 40px;text-align:center;">
                ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
              </td>
            </tr>
            
            <!-- Top Gradient Line -->
            <tr>
              <td style="padding:0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Greeting -->
            <tr>
              <td style="padding:32px 40px 0 40px;">
                <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${greeting}</p>
                <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${content.message}</p>
              </td>
            </tr>
            
            <!-- Reset Button -->
            <tr>
              <td style="padding:28px 40px 0 40px;text-align:center;">
                <a href="${resetLink}" style="display:inline-block;padding:14px 36px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.resetButton}</a>
              </td>
            </tr>
            
            <!-- Or copy link -->
            <tr>
              <td style="padding:20px 40px 0 40px;text-align:center;">
                <p style="margin:0 0 8px 0;color:#c0c0c0;font-size:12px;">${content.orCopyLink}</p>
                <p style="margin:0;color:#9ca3af;font-size:11px;line-height:18px;word-break:break-all;">${resetLink}</p>
              </td>
            </tr>
            
            <!-- Expiry Notice -->
            <tr>
              <td style="padding:24px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td style="background-color:#f9fafb;border-radius:8px;padding:14px 16px;text-align:center;">
                      <p style="margin:0;font-size:13px;color:#6b7280;">${content.expiry}</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Warning -->
            <tr>
              <td style="padding:20px 40px 0 40px;">
                <p style="margin:0;font-size:13px;color:#c0c0c0;line-height:20px;">${content.warning}</p>
              </td>
            </tr>
            
            <!-- Bottom Gradient Line -->
            <tr>
              <td style="padding:36px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Footer -->
            <tr>
              <td style="padding:20px 40px 32px 40px;text-align:center;">
                <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
              </td>
            </tr>
            
          </table>
        </td>
      </tr>
    </table>
    
  </body>
  </html>
        `;
  
        const mailDoc = {
          to: [email.trim().toLowerCase()],
          message: {
            subject: `${content.subject} — Nar24`,
            html: emailHtml,
          },
        };
  
        await admin.firestore().collection('mail').add(mailDoc);
  
        return {success: true};
      } catch (error) {
        console.error('Password reset email error:', error);
  
        // Don't reveal specific errors for security
        if (error.code === 'auth/user-not-found') {
          return {success: true};
        }
  
        throw new HttpsError('internal', 'Failed to send password reset email');
      }
    },
  );
  
  function getPasswordResetContent(languageCode) {
    const content = {
      en: {
        greeting: 'Hello',
        message: 'We received a request to reset your password. Click the button below to create a new password.',
        resetButton: 'Reset Password',
        orCopyLink: 'Or copy and paste this link in your browser:',
        expiry: 'This link expires in 1 hour.',
        warning: 'If you did not request a password reset, you can safely ignore this email. Your password will not be changed.',
        subject: 'Password Reset',
        rights: 'All rights reserved.',
      },
      tr: {
        greeting: 'Merhaba',
        message: 'Şifrenizi sıfırlamak için bir istek aldık. Yeni bir şifre oluşturmak için aşağıdaki butona tıklayın.',
        resetButton: 'Şifreyi Sıfırla',
        orCopyLink: 'Veya bu bağlantıyı tarayıcınıza yapıştırın:',
        expiry: 'Bu bağlantı 1 saat içinde sona erer.',
        warning: 'Şifre sıfırlama talebinde bulunmadıysanız bu e-postayı görmezden gelebilirsiniz. Şifreniz değiştirilmeyecektir.',
        subject: 'Şifre Sıfırlama',
        rights: 'Tüm hakları saklıdır.',
      },
      ru: {
        greeting: 'Здравствуйте',
        message: 'Мы получили запрос на сброс вашего пароля. Нажмите кнопку ниже, чтобы создать новый пароль.',
        resetButton: 'Сбросить пароль',
        orCopyLink: 'Или скопируйте и вставьте эту ссылку в браузер:',
        expiry: 'Срок действия ссылки — 1 час.',
        warning: 'Если вы не запрашивали сброс пароля, проигнорируйте это письмо. Ваш пароль не будет изменён.',
        subject: 'Сброс пароля',
        rights: 'Все права защищены.',
      },
    };
  
    return content[languageCode] || content.en;
  }
  
  export const sendReceiptEmail = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const {receiptId, orderId, email, isShopReceipt, shopId} = request.data;
      const context = request.auth;
  
      // Check if user is authenticated
      if (!context || !context.uid) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }
  
      const uid = context.uid;
  
      // Validate input
      if (!receiptId || !orderId || !email) {
        throw new HttpsError('invalid-argument', 'Missing required fields');
      }
  
      try {
        let receiptDoc;
        let ownerDoc;
        let displayName = 'Customer';
        let languageCode = 'en';
  
        // ✅ Support for shop receipts
        if (isShopReceipt && shopId) {
          receiptDoc = await admin.firestore()
            .collection('shops')
            .doc(shopId)
            .collection('receipts')
            .doc(receiptId)
            .get();
  
          if (!receiptDoc.exists) {
            throw new HttpsError('not-found', 'Receipt not found');
          }
  
          ownerDoc = await admin.firestore()
            .collection('shops')
            .doc(shopId)
            .get();
  
          if (ownerDoc.exists) {
            const shopData = ownerDoc.data();
            displayName = shopData.name || 'Shop';
            languageCode = shopData.languageCode || 'tr';
          }
        } else {
          ownerDoc = await admin.firestore()
            .collection('users')
            .doc(uid)
            .get();
  
          const userData = ownerDoc.data() || {};
          languageCode = userData.languageCode || 'en';
          displayName = userData.displayName || 'Customer';
  
          receiptDoc = await admin.firestore()
            .collection('users')
            .doc(uid)
            .collection('receipts')
            .doc(receiptId)
            .get();
  
          if (!receiptDoc.exists) {
            throw new HttpsError('not-found', 'Receipt not found');
          }
  
          const receiptData = receiptDoc.data();
  
          if (receiptData.buyerId !== uid) {
            throw new HttpsError('permission-denied', 'Access denied');
          }
        }
  
        const receiptData = receiptDoc.data();
  
        // Get logo URL from Storage
        let logoUrl = '';
        try {
          const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
          const logoFile = bucket.file('assets/naricon.png');
          const [exists] = await logoFile.exists();
          if (exists) {
            const [url] = await logoFile.getSignedUrl({
              action: 'read',
              expires: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
            });
            logoUrl = url;
          }
        } catch (err) {
          console.warn('Could not get logo URL:', err.message);
        }
  
        // Get PDF download URL
        let pdfUrl = null;
        try {
          const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
  
          if (receiptData.filePath) {
            const file = bucket.file(receiptData.filePath);
            const [url] = await file.getSignedUrl({
              action: 'read',
              expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
            });
            pdfUrl = url;
          } else {
            const fallbackPath = `receipts/${orderId}.pdf`;
            const file = bucket.file(fallbackPath);
            const [exists] = await file.exists();
            if (exists) {
              const [url] = await file.getSignedUrl({
                action: 'read',
                expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
              });
              pdfUrl = url;
            }
          }
        } catch (error) {
          console.error('Error generating download URL:', error);
        }
  
        const content = getLocalizedContent(languageCode);
        const orderIdShort = orderId.substring(0, 8).toUpperCase();
        const receiptIdShort = receiptId.substring(0, 8).toUpperCase();
  
        const orderDate = receiptData.createdAt ?
          new Date(receiptData.createdAt.toDate()).toLocaleDateString(
            languageCode === 'tr' ? 'tr-TR' : languageCode === 'ru' ? 'ru-RU' : 'en-US', {
              year: 'numeric',
              month: 'long',
              day: 'numeric',
            }) : new Date().toLocaleDateString();
  
        const isBoost = receiptData.receiptType === 'boost';
  
        const emailHtml = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!--[if mso]>
    <noscript>
      <xml>
        <o:OfficeDocumentSettings>
          <o:PixelsPerInch>96</o:PixelsPerInch>
        </o:OfficeDocumentSettings>
      </xml>
    </noscript>
    <![endif]-->
  </head>
  <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
    
    <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
      <tr>
        <td align="center">
          <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
            
            <!-- Logo -->
            <tr>
              <td style="padding:32px 40px 24px 40px;text-align:center;">
                ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:44px;height:44px;border-radius:10px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
              </td>
            </tr>
            
            <!-- Top Gradient Line -->
            <tr>
              <td style="padding:0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Greeting -->
            <tr>
              <td style="padding:32px 40px 0 40px;">
                <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${content.greeting} ${displayName},</p>
                <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${isBoost ? content.boostMessage : content.message}</p>
              </td>
            </tr>
            
            <!-- Details -->
            <tr>
              <td style="padding:28px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  
                  <!-- Order/Boost ID -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${isBoost ? content.boostLabel : content.orderLabel}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">#${orderIdShort}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Receipt ID -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.receiptLabel}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">#${receiptIdShort}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Date -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.dateLabel}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${orderDate}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Payment Method -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.paymentLabel}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${receiptData.paymentMethod || 'Card'}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
  
  ${isBoost && receiptData.boostDuration ? `
                  <!-- Boost Duration -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.durationLabel}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${receiptData.boostDuration} ${content.minutesUnit}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Boosted Items -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.itemsLabel}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${receiptData.itemCount || 1}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
  ` : ''}
                  
                  <!-- Total -->
                  <tr>
                    <td style="padding:16px 0 0 0;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#1a1a1a;font-size:14px;font-weight:600;">${content.totalLabel}</td>
                          <td align="right" style="color:#ff6b35;font-size:22px;font-weight:700;letter-spacing:-0.3px;">${receiptData.totalPrice.toFixed(0)} ${receiptData.currency || 'TL'}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                </table>
              </td>
            </tr>
  
  ${pdfUrl ? `
            <!-- Download Button -->
            <tr>
              <td style="padding:32px 40px 0 40px;text-align:center;">
                <a href="${pdfUrl}" style="display:inline-block;padding:12px 32px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.downloadButton}</a>
              </td>
            </tr>
  ` : ''}
            
            <!-- Bottom Gradient Line -->
            <tr>
              <td style="padding:36px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Footer -->
            <tr>
              <td style="padding:20px 40px 32px 40px;text-align:center;">
                <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
              </td>
            </tr>
            
          </table>
        </td>
      </tr>
    </table>
    
  </body>
  </html>
        `;
  
        const mailDoc = {
          to: [email],
          message: {
            subject: `${content.subject} #${orderIdShort} — Nar24`,
            html: emailHtml,
          },
          template: {
            name: 'receipt',
            data: {
              receiptId,
              orderId,
              type: isBoost ? 'boost_receipt' : 'order_receipt',
            },
          },
        };
  
        await admin.firestore().collection('mail').add(mailDoc);
  
        return {
          success: true,
          message: 'Email sent successfully',
        };
      } catch (error) {
        console.error('Error:', error);
        if (error instanceof HttpsError) {
          throw error;
        }
        throw new HttpsError('internal', 'Failed to send email');
      }
    },
  );
  
  function getLocalizedContent(languageCode) {
    const content = {
      en: {
        greeting: 'Hello',
        message: 'Thank you for your purchase. Here are your receipt details.',
        boostMessage: 'Your boost payment was successful. Here are the details.',
        orderLabel: 'Order',
        boostLabel: 'Boost',
        receiptLabel: 'Receipt',
        dateLabel: 'Date',
        paymentLabel: 'Payment',
        durationLabel: 'Duration',
        itemsLabel: 'Items Boosted',
        minutesUnit: 'min',
        totalLabel: 'Total',
        subject: 'Receipt',
        downloadButton: 'Download PDF',
        rights: 'All rights reserved.',
      },
      tr: {
        greeting: 'Merhaba',
        message: 'Satın alımınız için teşekkür ederiz. Fatura detaylarınız aşağıdadır.',
        boostMessage: 'Boost ödemeniz başarılı. Detaylar aşağıdadır.',
        orderLabel: 'Sipariş',
        boostLabel: 'Boost',
        receiptLabel: 'Fatura',
        dateLabel: 'Tarih',
        paymentLabel: 'Ödeme',
        durationLabel: 'Süre',
        itemsLabel: 'Boost Edilen',
        minutesUnit: 'dk',
        totalLabel: 'Toplam',
        subject: 'Fatura',
        downloadButton: 'PDF İndir',
        rights: 'Tüm hakları saklıdır.',
      },
      ru: {
        greeting: 'Здравствуйте',
        message: 'Спасибо за покупку. Детали вашего чека ниже.',
        boostMessage: 'Оплата буста прошла успешно. Детали ниже.',
        orderLabel: 'Заказ',
        boostLabel: 'Буст',
        receiptLabel: 'Чек',
        dateLabel: 'Дата',
        paymentLabel: 'Оплата',
        durationLabel: 'Длительность',
        itemsLabel: 'Товаров',
        minutesUnit: 'мин',
        totalLabel: 'Итого',
        subject: 'Чек',
        downloadButton: 'Скачать PDF',
        rights: 'Все права защищены.',
      },
    };
  
    return content[languageCode] || content.en;
  }
  
  export const sendReportEmail = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const {reportId, shopId, email} = request.data;
      const context = request.auth;
  
      // Check if user is authenticated
      if (!context || !context.uid) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }
  
      const uid = context.uid;
  
      // Validate input
      if (!reportId || !shopId || !email) {
        throw new HttpsError('invalid-argument', 'Missing required fields');
      }
  
      try {
        // Get user's language preference
        const userDoc = await admin.firestore()
          .collection('users')
          .doc(uid)
          .get();
  
        const userData = userDoc.data() || {};
        const languageCode = userData.languageCode || 'en';
        const displayName = userData.displayName || 'Shop Owner';
  
        // Get report data
        const reportDoc = await admin.firestore()
          .collection('shops')
          .doc(shopId)
          .collection('reports')
          .doc(reportId)
          .get();
  
        if (!reportDoc.exists) {
          throw new HttpsError('not-found', 'Report not found');
        }
  
        const reportData = reportDoc.data();
  
        // Get shop data
        const shopDoc = await admin.firestore()
          .collection('shops')
          .doc(shopId)
          .get();
  
        const shopData = shopDoc.data() || {};
        const shopName = shopData.name || 'Unknown Shop';
  
        // Verify ownership or access
        if (shopData.ownerId !== uid && !shopData.managers?.includes(uid)) {
          throw new HttpsError('permission-denied', 'Access denied');
        }
  
        // Get logo URL from Storage
        let logoUrl = '';
        try {
          const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
          const logoFile = bucket.file('assets/naricon.png');
          const [exists] = await logoFile.exists();
          if (exists) {
            const [url] = await logoFile.getSignedUrl({
              action: 'read',
              expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
            });
            logoUrl = url;
          }
        } catch (err) {
          console.warn('Could not get logo URL:', err.message);
        }
  
        // Get localized content
        const content = getReportLocalizedContent(languageCode);
        const reportIdShort = reportId.substring(0, 8).toUpperCase();
  
        // Format dates
        const createdAt = reportData.createdAt?.toDate() || new Date();
        const formattedDate = createdAt.toLocaleDateString(
          languageCode === 'tr' ? 'tr-TR' : languageCode === 'ru' ? 'ru-RU' : 'en-US',
          {year: 'numeric', month: 'long', day: 'numeric'},
        );
  
        // Format date range if exists
        let dateRangeText = '';
        if (reportData.dateRange) {
          const startDate = reportData.dateRange.start.toDate();
          const endDate = reportData.dateRange.end.toDate();
          dateRangeText = `${startDate.toLocaleDateString()} - ${endDate.toLocaleDateString()}`;
        }
  
        // Build included data tags
        const includedTags = [];
        if (reportData.includeProducts) includedTags.push(content.products);
        if (reportData.includeOrders) includedTags.push(content.orders);
        if (reportData.includeBoostHistory) includedTags.push(content.boostHistory);
        const includedText = includedTags.join(', ');
  
        // Generate report URL
        let pdfUrl = null;
        try {
          const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
  
          if (reportData.filePath) {
            const file = bucket.file(reportData.filePath);
            const [url] = await file.getSignedUrl({
              action: 'read',
              expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
            });
            pdfUrl = url;
          } else {
            const possiblePaths = [
              `reports/${shopId}/${reportId}.pdf`,
            ];
  
            for (const filePath of possiblePaths) {
              try {
                const file = bucket.file(filePath);
                const [exists] = await file.exists();
                if (exists) {
                  const [url] = await file.getSignedUrl({
                    action: 'read',
                    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
                  });
                  pdfUrl = url;
                  break;
                }
              } catch (error) {
                continue;
              }
            }
  
            if (!pdfUrl) {
              try {
                const [files] = await bucket.getFiles({
                  prefix: `reports/${shopId}/${reportId}`,
                });
  
                if (files.length > 0) {
                  const sortedFiles = files.sort((a, b) => b.name.localeCompare(a.name));
                  const [url] = await sortedFiles[0].getSignedUrl({
                    action: 'read',
                    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
                  });
                  pdfUrl = url;
                }
              } catch (error) {
                console.error('Error searching for report file:', error);
              }
            }
          }
        } catch (error) {
          console.error('Error generating download URL:', error);
        }
  
        const emailHtml = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!--[if mso]>
    <noscript>
      <xml>
        <o:OfficeDocumentSettings>
          <o:PixelsPerInch>96</o:PixelsPerInch>
        </o:OfficeDocumentSettings>
      </xml>
    </noscript>
    <![endif]-->
  </head>
  <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
    
    <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
      <tr>
        <td align="center">
          <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
            
            <!-- Logo -->
            <tr>
              <td style="padding:32px 40px 24px 40px;text-align:center;">
                ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
              </td>
            </tr>
            
            <!-- Top Gradient Line -->
            <tr>
              <td style="padding:0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Greeting -->
            <tr>
              <td style="padding:32px 40px 0 40px;">
                <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${content.greeting} ${displayName},</p>
                <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${content.message}</p>
              </td>
            </tr>
            
            <!-- Details -->
            <tr>
              <td style="padding:28px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  
                  <!-- Report Name -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.reportName}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${reportData.reportName || 'Report'}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Report ID -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.reportId}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">#${reportIdShort}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Shop Name -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.shopName}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${shopName}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Date -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.generatedOn}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${formattedDate}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
  
  ${dateRangeText ? `
                  <!-- Date Range -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.dateRange}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${dateRangeText}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
  ` : ''}
                  
                  <!-- Included Data -->
                  <tr>
                    <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.includedData}</td>
                          <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${includedText || '—'}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                </table>
              </td>
            </tr>
  
  ${pdfUrl ? `
            <!-- Download Button -->
            <tr>
              <td style="padding:32px 40px 0 40px;text-align:center;">
                <a href="${pdfUrl}" style="display:inline-block;padding:12px 32px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.downloadButton}</a>
              </td>
            </tr>
  ` : ''}
            
            <!-- Bottom Gradient Line -->
            <tr>
              <td style="padding:36px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Footer -->
            <tr>
              <td style="padding:20px 40px 32px 40px;text-align:center;">
                <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
              </td>
            </tr>
            
          </table>
        </td>
      </tr>
    </table>
    
  </body>
  </html>
        `;
  
        // Create mail document for SendGrid
        const mailDoc = {
          to: [email],
          message: {
            subject: `${content.subject}: ${reportData.reportName || 'Report'} — Nar24`,
            html: emailHtml,
          },
          template: {
            name: 'report',
            data: {
              reportId,
              shopId,
              type: 'shop_report',
            },
          },
        };
  
        // Send email via SendGrid extension
        await admin.firestore().collection('mail').add(mailDoc);
  
        return {
          success: true,
          message: 'Email sent successfully',
        };
      } catch (error) {
        console.error('Error:', error);
        if (error instanceof HttpsError) {
          throw error;
        }
        throw new HttpsError('internal', 'Failed to send email');
      }
    },
  );
  
  function getReportLocalizedContent(languageCode) {
    const content = {
      en: {
        greeting: 'Hello',
        message: 'Your shop report is ready. Here are the details.',
        reportName: 'Report',
        reportId: 'Report ID',
        shopName: 'Shop',
        generatedOn: 'Date',
        dateRange: 'Period',
        includedData: 'Includes',
        products: 'Products',
        orders: 'Orders',
        boostHistory: 'Boost History',
        subject: 'Report',
        downloadButton: 'Download PDF',
        rights: 'All rights reserved.',
      },
      tr: {
        greeting: 'Merhaba',
        message: 'Mağaza raporunuz hazır. Detaylar aşağıdadır.',
        reportName: 'Rapor',
        reportId: 'Rapor No',
        shopName: 'Mağaza',
        generatedOn: 'Tarih',
        dateRange: 'Dönem',
        includedData: 'İçerik',
        products: 'Ürünler',
        orders: 'Siparişler',
        boostHistory: 'Boost Geçmişi',
        subject: 'Rapor',
        downloadButton: 'PDF İndir',
        rights: 'Tüm hakları saklıdır.',
      },
      ru: {
        greeting: 'Здравствуйте',
        message: 'Отчёт вашего магазина готов. Детали ниже.',
        reportName: 'Отчёт',
        reportId: 'Номер отчёта',
        shopName: 'Магазин',
        generatedOn: 'Дата',
        dateRange: 'Период',
        includedData: 'Содержание',
        products: 'Товары',
        orders: 'Заказы',
        boostHistory: 'История бустов',
        subject: 'Отчёт',
        downloadButton: 'Скачать PDF',
        rights: 'Все права защищены.',
      },
    };
  
    return content[languageCode] || content.en;
  }
  
  export const shopWelcomeEmail = onCall(
    {region: 'europe-west3'},
    async (request) => {
      const {shopId, email} = request.data;
      const context = request.auth;
  
      if (!context || !context.uid) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }
  
      if (!shopId || !email) {
        throw new HttpsError('invalid-argument', 'Missing required fields: shopId and email');
      }
  
      try {
        // Get shop data
        const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
  
        if (!shopDoc.exists) {
          throw new HttpsError('not-found', 'Shop not found');
        }
  
        const shopData = shopDoc.data();
        const shopName = shopData.name || 'Shop';
        const ownerName = shopData.ownerName || 'Seller';
  
        // Get user's language preference
        const userDoc = await admin.firestore()
          .collection('users')
          .doc(context.uid)
          .get();
        const userData = userDoc.data() || {};
        const languageCode = userData.languageCode || 'tr';
  
        const content = getWelcomeLocalizedContent(languageCode);
  
        // Get signed URLs for email images
        const bucket = admin.storage().bucket();
        const imageUrls = {};
  
        const images = [
          {key: 'logo', path: 'assets/naricon.png'},
          {key: 'welcome', path: 'assets/shopwelcome.png'},
          {key: 'products', path: 'assets/shopproducts.png'},
          {key: 'boost', path: 'assets/shopboost.png'},
        ];
  
        try {
          for (const img of images) {
            const file = bucket.file(img.path);
            const [exists] = await file.exists();
            if (exists) {
              const [url] = await file.getSignedUrl({
                action: 'read',
                expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
              });
              imageUrls[img.key] = url;
            }
          }
        } catch (error) {
          console.error('Error loading email images:', error);
        }
  
        const emailHtml = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!--[if mso]>
    <noscript>
      <xml>
        <o:OfficeDocumentSettings>
          <o:PixelsPerInch>96</o:PixelsPerInch>
        </o:OfficeDocumentSettings>
      </xml>
    </noscript>
    <![endif]-->
  </head>
  <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
    
    <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
      <tr>
        <td align="center">
          <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
            
            <!-- Logo -->
            <tr>
              <td style="padding:32px 40px 24px 40px;text-align:center;">
                ${imageUrls.logo ? `<img src="${imageUrls.logo}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
              </td>
            </tr>
            
            <!-- Top Gradient Line -->
            <tr>
              <td style="padding:0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
  
            <!-- Welcome Image -->
            ${imageUrls.welcome ? `
            <tr>
              <td style="padding:32px 40px 0 40px;text-align:center;">
                <img src="${imageUrls.welcome}" alt="Welcome" width="100" height="100" style="display:inline-block;width:100px;height:100px;" />
              </td>
            </tr>
            ` : ''}
            
            <!-- Greeting -->
            <tr>
              <td style="padding:24px 40px 0 40px;text-align:center;">
                <h2 style="margin:0 0 12px 0;color:#1a1a1a;font-size:22px;font-weight:700;line-height:1.3;">${content.title}</h2>
                <p style="margin:0;color:#6b7280;font-size:14px;line-height:22px;">
                  ${content.greeting} <span style="color:#1a1a1a;font-weight:600;">${ownerName}</span>, 
                  <span style="color:#ff6b35;font-weight:600;">${shopName}</span> ${content.approved}
                </p>
              </td>
            </tr>
            
            <!-- Feature Cards -->
            <tr>
              <td style="padding:32px 40px 0 40px;">
                
                <!-- Feature 1: Products -->
                <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:16px;">
                  <tr>
                    <td style="padding:20px;background-color:#f9fafb;border-radius:12px;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          ${imageUrls.products ? `
                          <td width="56" valign="top">
                            <img src="${imageUrls.products}" alt="" width="48" height="48" style="display:block;width:48px;height:48px;border-radius:10px;" />
                          </td>
                          ` : `
                          <td width="56" valign="top">
                            <div style="width:48px;height:48px;background-color:#e0f2fe;border-radius:10px;text-align:center;line-height:48px;font-size:22px;">📦</div>
                          </td>
                          `}
                          <td style="padding-left:14px;">
                            <p style="margin:0 0 4px 0;color:#1a1a1a;font-size:14px;font-weight:600;">${content.productsTitle}</p>
                            <p style="margin:0;color:#9ca3af;font-size:13px;line-height:19px;">${content.productsDesc}</p>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>
                
                <!-- Feature 2: Boost -->
                <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:16px;">
                  <tr>
                    <td style="padding:20px;background-color:#f9fafb;border-radius:12px;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          ${imageUrls.boost ? `
                          <td width="56" valign="top">
                            <img src="${imageUrls.boost}" alt="" width="48" height="48" style="display:block;width:48px;height:48px;border-radius:10px;" />
                          </td>
                          ` : `
                          <td width="56" valign="top">
                            <div style="width:48px;height:48px;background-color:#fef3c7;border-radius:10px;text-align:center;line-height:48px;font-size:22px;">🚀</div>
                          </td>
                          `}
                          <td style="padding-left:14px;">
                            <p style="margin:0 0 4px 0;color:#1a1a1a;font-size:14px;font-weight:600;">${content.boostTitle}</p>
                            <p style="margin:0;color:#9ca3af;font-size:13px;line-height:19px;">${content.boostDesc}</p>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>
                
              </td>
            </tr>
            
            <!-- Quick Start Steps -->
            <tr>
              <td style="padding:8px 40px 0 40px;">
                <p style="margin:0 0 14px 0;color:#1a1a1a;font-size:14px;font-weight:600;">${content.quickStart}</p>
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td style="padding:8px 0;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="28" valign="top">
                            <div style="width:22px;height:22px;background-color:#ff6b35;color:#ffffff;border-radius:50%;text-align:center;line-height:22px;font-size:11px;font-weight:700;">1</div>
                          </td>
                          <td style="color:#6b7280;font-size:13px;line-height:20px;">${content.step1}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:8px 0;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="28" valign="top">
                            <div style="width:22px;height:22px;background-color:#ff6b35;color:#ffffff;border-radius:50%;text-align:center;line-height:22px;font-size:11px;font-weight:700;">2</div>
                          </td>
                          <td style="color:#6b7280;font-size:13px;line-height:20px;">${content.step2}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:8px 0;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="28" valign="top">
                            <div style="width:22px;height:22px;background-color:#ff6b35;color:#ffffff;border-radius:50%;text-align:center;line-height:22px;font-size:11px;font-weight:700;">3</div>
                          </td>
                          <td style="color:#6b7280;font-size:13px;line-height:20px;">${content.step3}</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- CTA Button -->
            <tr>
              <td style="padding:28px 40px 0 40px;text-align:center;">
                <a href="https://www.nar24panel.com/" style="display:inline-block;padding:14px 36px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.ctaButton}</a>
              </td>
            </tr>
            
            <!-- Bottom Gradient Line -->
            <tr>
              <td style="padding:36px 40px 0 40px;">
                <table cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                    <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                  </tr>
                </table>
              </td>
            </tr>
            
            <!-- Footer -->
            <tr>
              <td style="padding:20px 40px 32px 40px;text-align:center;">
                <p style="margin:0 0 6px 0;color:#9ca3af;font-size:12px;">${content.supportText} <a href="mailto:support@nar24.com" style="color:#ff6b35;text-decoration:none;font-weight:500;">support@nar24.com</a></p>
                <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
              </td>
            </tr>
            
          </table>
        </td>
      </tr>
    </table>
    
  </body>
  </html>
        `;
  
        const mailDoc = {
          to: [email],
          message: {
            subject: `${content.subject} — Nar24`,
            html: emailHtml,
          },
          template: {
            name: 'shop_welcome',
            data: {
              shopId,
              shopName,
              type: 'shop_approval',
            },
          },
        };
  
        await admin.firestore().collection('mail').add(mailDoc);
  
        await admin.firestore().collection('shops').doc(shopId).update({
          welcomeEmailSent: true,
          welcomeEmailSentAt: new Date(),
        });
  
        return {
          success: true,
          message: 'Welcome email sent successfully',
          shopName,
        };
      } catch (error) {
        console.error('Error sending shop welcome email:', error);
        if (error instanceof HttpsError) {
          throw error;
        }
        throw new HttpsError('internal', 'Failed to send welcome email');
      }
    },
  );
  
  function getWelcomeLocalizedContent(languageCode) {
    const content = {
      en: {
        title: 'You Are Now an Authorized Seller!',
        greeting: 'Hello',
        approved: 'has been approved and is ready for sales!',
        productsTitle: 'List Your Products Easily',
        productsDesc: 'Upload your products in minutes and start selling right away with our advanced panel.',
        boostTitle: 'Boost Your Products',
        boostDesc: 'Highlight your products to reach wider audiences and increase your sales.',
        quickStart: 'Quick Start',
        step1: 'Add your first products with detailed descriptions',
        step2: 'Use quality photos to showcase your products',
        step3: 'Boost popular products to get more visibility',
        ctaButton: 'Go to Shop Panel',
        supportText: 'Need help?',
        rights: 'All rights reserved.',
        subject: 'Your Shop Has Been Approved',
      },
      tr: {
        title: 'Yetkili Satıcı Oldunuz!',
        greeting: 'Merhaba',
        approved: 'mağazanız onaylandı ve satışa hazır!',
        productsTitle: 'Ürünlerinizi Kolayca Listeleyin',
        productsDesc: 'Gelişmiş panelimiz ile ürünlerinizi dakikalar içinde yükleyip hemen satışa sunun.',
        boostTitle: 'Ürünlerinizi Öne Çıkarın',
        boostDesc: 'Ürünlerinizi boost ederek daha geniş kitlelere ulaşın ve satışlarınızı artırın.',
        quickStart: 'Hızlı Başlangıç',
        step1: 'İlk ürünlerinizi detaylı açıklamalarla ekleyin',
        step2: 'Kaliteli fotoğraflar ile ürünlerinizi sergileyin',
        step3: 'Popüler ürünlerinizi boost ederek öne çıkarın',
        ctaButton: 'Mağaza Paneline Git',
        supportText: 'Yardıma mı ihtiyacınız var?',
        rights: 'Tüm hakları saklıdır.',
        subject: 'Mağazanız Onaylandı',
      },
      ru: {
        title: 'Вы стали авторизованным продавцом!',
        greeting: 'Здравствуйте',
        approved: 'ваш магазин одобрен и готов к продажам!',
        productsTitle: 'Легко размещайте товары',
        productsDesc: 'Загружайте товары за считанные минуты и сразу начинайте продавать через нашу панель.',
        boostTitle: 'Продвигайте свои товары',
        boostDesc: 'Выделяйте товары с помощью буста, чтобы охватить больше покупателей и увеличить продажи.',
        quickStart: 'Быстрый старт',
        step1: 'Добавьте первые товары с подробными описаниями',
        step2: 'Используйте качественные фотографии для демонстрации',
        step3: 'Продвигайте популярные товары для большей видимости',
        ctaButton: 'Перейти в панель магазина',
        supportText: 'Нужна помощь?',
        rights: 'Все права защищены.',
        subject: 'Ваш магазин одобрен',
      },
    };

    return content[languageCode] || content.tr;
  }

// Idempotent, transactional creation/patching of users/{uid}.
// Safe to call any number of times from any auth path — never clobbers
// existing fields, only fills in what's missing. This is the canonical
// path for user doc creation and self-healing on orphan Auth accounts.
export const ensureUserDocument = onCall(
    {region: 'europe-west3'},
    async (request) => {
      if (!request.auth || !request.auth.uid) {
        throw new HttpsError(
            'unauthenticated',
            'Must be signed in to ensure user document.',
        );
      }

      const uid = request.auth.uid;
      const clientLanguageCode =
        typeof request.data?.languageCode === 'string' &&
        request.data.languageCode.length > 0 ?
          request.data.languageCode :
          null;

      let userRecord;
      try {
        userRecord = await admin.auth().getUser(uid);
      } catch (err) {
        throw new HttpsError(
            'internal',
            'Failed to read Auth user: ' + err.message,
        );
      }

      const docRef = admin.firestore().collection('users').doc(uid);
      let created = false;

      try {
        await admin.firestore().runTransaction(async (tx) => {
          const snap = await tx.get(docRef);
          const existing = snap.exists ? snap.data() || {} : null;
          const now = admin.firestore.FieldValue.serverTimestamp();

          const payload = {};

          if (!existing) {
            created = true;
            // Fresh doc — write full defaults.
            payload.email = userRecord.email || '';
            payload.displayName = userRecord.displayName || null;
            payload.isNew = true;
            payload.isVerified = !!userRecord.emailVerified;
            payload.referralCode = uid;
            payload.createdAt = now;
            payload.languageCode = clientLanguageCode || 'tr';
            if (userRecord.emailVerified) {
              payload.emailVerifiedAt = now;
            }
          } else {
            // Existing doc — patch only missing required fields.
            if (existing.email == null || existing.email === '') {
              if (userRecord.email) payload.email = userRecord.email;
            }
            if (existing.createdAt == null) payload.createdAt = now;
            if (existing.referralCode == null) payload.referralCode = uid;
            if (existing.languageCode == null) {
              payload.languageCode = clientLanguageCode || 'tr';
            }
            // Sync verification if Auth is verified but doc isn't marked.
            if (userRecord.emailVerified && existing.isVerified !== true) {
              payload.isVerified = true;
              if (existing.emailVerifiedAt == null) {
                payload.emailVerifiedAt = now;
              }
            }
          }

          if (Object.keys(payload).length > 0) {
            tx.set(docRef, payload, {merge: true});
          }
        });
      } catch (err) {
        throw new HttpsError(
            'internal',
            'Failed to ensure user document: ' + err.message,
        );
      }

      return {
        ok: true,
        created,
        uid,
      };
    },
);

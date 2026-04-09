import crypto from 'crypto';                                                                                                                                                                                                                              
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';                                                                                                                                                                                                                       
import {authenticator} from 'otplib';
import {defineSecret} from 'firebase-functions/params';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {Timestamp, FieldValue} from 'firebase-admin/firestore';

const OTP_SALT = defineSecret('OTP_SALT');


function getLocalizedTemplate(language, type) {
    const lang = emailTemplates[language] || emailTemplates['en'];
    const template = lang[type] || lang['default'];
    return {...lang, ...template};
  }
  
  function generateEmailHTML(template, code) {
    const gradientColors = {
      setup: 'linear-gradient(135deg, #ff6b35, #e91e63)',
      login: 'linear-gradient(135deg, #4caf50, #2196f3)',
      disable: 'linear-gradient(135deg, #ff9800, #f44336)',
      default: 'linear-gradient(135deg, #ff6b35, #e91e63)',
    };
    const gradient = gradientColors[template.type] || gradientColors.default;
  
    const warningSection = template.warning ? `
        <div style="background:#ffebee;border-left:4px solid #f44336;padding:15px;margin:20px 0;">
          <p style="margin:0;color:#c62828;font-weight:bold;">${template.warning}</p>
        </div>` : '';
  
    return `
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;">
        <div style="text-align:center;margin-bottom:30px;">
          <h1 style="color:#ff6b35;margin:0;">${template.brandName}</h1>
        </div>
        <h2 style="color:#333;text-align:center;">${template.title}</h2>
        <p style="color:#555;font-size:16px;line-height:1.6;">${template.description}</p>
        <div style="background:${gradient};padding:25px;text-align:center;margin:30px 0;border-radius:12px;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
          <h3 style="margin:0;font-size:36px;letter-spacing:8px;color:white;font-weight:bold;">${code}</h3>
        </div>
        <div style="background:#fff3e0;border-left:4px solid #ff9800;padding:15px;margin:20px 0;">
          <p style="margin:0;color:#e65100;font-weight:bold;">⏰ ${template.expiresIn}</p>
        </div>
        ${warningSection}
        <p style="color:#555;font-size:14px;">${template.securityNote || ''}</p>
        <hr style="margin:30px 0;border:none;border-top:1px solid #eee;">
        <p style="color:#999;font-size:12px;text-align:center;">${template.automatedMessage}<br>${template.copyright}</p>
      </div>
    `;
  }

  const emailTemplates = {
    en: {
      brandName: 'Nar24',
      copyright: '© 2024 Nar24. All rights reserved.',
      automatedMessage:
        'This is an automated message from Nar24. Please do not reply to this email.',
      setup: {
        subject: 'Nar24 - Two-Factor Authentication Setup',
        title: 'Two-Factor Authentication Setup',
        description:
          'You are setting up two-factor authentication for your Nar24 account. Please enter the verification code below in your app:',
        expiresIn: 'This code expires in 10 minutes',
        securityNote:
          'If you did not request this setup, please contact our support team immediately.',
      },
      login: {
        subject: 'Nar24 - Login Verification Code',
        title: 'Login Verification Required',
        description:
          'Someone is trying to sign in to your Nar24 account. Enter the verification code below to complete your login:',
        expiresIn: 'This code expires in 5 minutes',
        securityNote:
          '🚨 If you did not try to sign in, please secure your account immediately by changing your password.',
      },
      disable: {
        subject: 'Nar24 - Disable Two-Factor Authentication',
        title: 'Disable Two-Factor Authentication',
        description:
          'You are about to disable two-factor authentication for your Nar24 account. Enter the verification code below to confirm:',
        expiresIn: 'This code expires in 10 minutes',
        securityNote:
          'If you did not request this change, please contact our support team immediately.',
        warning: '⚠️ Warning: Disabling 2FA will make your account less secure.',
      },
      default: {
        subject: 'Nar24 - Verification Code',
        title: 'Verification Code',
        description: 'Your Nar24 verification code is:',
        expiresIn: 'This code expires in 10 minutes',
      },
    },
    tr: {
      brandName: 'Nar24',
      copyright: '© 2024 Nar24. Tüm hakları saklıdır.',
      automatedMessage:
        'Bu Nar24 tarafından otomatik bir mesajdır. Lütfen bu e-postayı yanıtlamayın.',
      setup: {
        subject: 'Nar24 - İki Faktörlü Doğrulama Kurulumu',
        title: 'İki Faktörlü Doğrulama Kurulumu',
        description:
          'Nar24 hesabınız için iki faktörlü doğrulama kuruluyor. Lütfen aşağıdaki doğrulama kodunu uygulamanızda girin:',
        expiresIn: 'Bu kod 10 dakika içinde sona erer',
        securityNote:
          'Bu kurulumu talep etmediyseniz, lütfen destek ekibimizle hemen iletişime geçin.',
      },
      login: {
        subject: 'Nar24 - Giriş Doğrulama Kodu',
        title: 'Giriş Doğrulaması Gerekli',
        description:
          'Birisi Nar24 hesabınızda oturum açmaya çalışıyor. Girişinizi tamamlamak için aşağıdaki doğrulama kodunu girin:',
        expiresIn: 'Bu kod 5 dakika içinde sona erer',
        securityNote:
          '🚨 Giriş yapmaya çalışmadıysanız, lütfen şifrenizi değiştirerek hesabınızı hemen güvence altına alın.',
      },
      disable: {
        subject: 'Nar24 - İki Faktörlü Doğrulamayı Devre Dışı Bırak',
        title: 'İki Faktörlü Doğrulamayı Devre Dışı Bırak',
        description:
          'Nar24 hesabınızda iki faktörlü doğrulamayı devre dışı bırakmak üzeresiniz. Onaylamak için aşağıdaki doğrulama kodunu girin:',
        expiresIn: 'Bu kod 10 dakika içinde sona erer',
        securityNote:
          'Bu değişikliği talep etmediyseniz, lütfen destek ekibimizle hemen iletişime geçin.',
        warning:
          '⚠️ Uyarı: 2FAyı devre dışı bırakmak hesabınızı daha az güvenli hale getirir.',
      },
      default: {
        subject: 'Nar24 - Doğrulama Kodu',
        title: 'Doğrulama Kodu',
        description: 'Nar24 doğrulama kodunuz:',
        expiresIn: 'Bu kod 10 dakika içinde sona erer',
      },
    },
    ru: {
      brandName: 'Nar24',
      copyright: '© 2024 Nar24. Все права защищены.',
      automatedMessage:
        'Это автоматическое сообщение от Nar24. Пожалуйста, не отвечайте на это письмо.',
      setup: {
        subject: 'Nar24 - Настройка двухфакторной аутентификации',
        title: 'Настройка двухфакторной аутентификации',
        description:
          'Вы настраиваете двухфакторную аутентификацию для своей учетной записи Nar24. Пожалуйста, введите код подтверждения ниже в вашем приложении:',
        expiresIn: 'Этот код истекает через 10 минут',
        securityNote:
          'Если вы не запрашивали эту настройку, немедленно обратитесь в нашу службу поддержки.',
      },
      login: {
        subject: 'Nar24 - Код подтверждения входа',
        title: 'Требуется подтверждение входа',
        description:
          'Кто-то пытается войти в вашу учетную запись Nar24. Введите код подтверждения ниже, чтобы завершить вход:',
        expiresIn: 'Этот код истекает через 5 минут',
        securityNote:
          '🚨 Если вы не пытались войти в систему, немедленно защитите свою учетную запись, изменив пароль.',
      },
      disable: {
        subject: 'Nar24 - Отключить двухфакторную аутентификацию',
        title: 'Отключить двухфакторную аутентификацию',
        description:
          'Вы собираетесь отключить двухфакторную аутентификацию для своей учетной записи Nar24. Введите код подтверждения ниже для подтверждения:',
        expiresIn: 'Этот код истекает через 10 минут',
        securityNote:
          'Если вы не запрашивали это изменение, немедленно обратитесь в нашу службу поддержки.',
        warning:
          '⚠️ Предупреждение: Отключение 2FA сделает вашу учетную запись менее безопасной.',
      },
      default: {
        subject: 'Nar24 - Код подтверждения',
        title: 'Код подтверждения',
        description: 'Ваш код подтверждения Nar24:',
        expiresIn: 'Этот код истекает через 10 минут',
      },
    },
  };

/**
 * ──────────────────────────────────────────────────────────────────────────────
 * TOTP helpers
 * ──────────────────────────────────────────────────────────────────────────────
 */
const ISSUER = 'Nar24';

// Otplib defaults: 6 digits, 30s step, SHA-1 — matches authenticator apps.
authenticator.options = {digits: 6, step: 30};

function hmac(code) {
  const salt = OTP_SALT.value();
  return crypto.createHmac('sha256', salt).update(code).digest('hex');
}

function secureRandom6() {
  const max = 999999;
  const min = 0;
  const range = max - min + 1;
  const bytesNeeded = Math.ceil(Math.log2(range) / 8);
  const maxValid = Math.pow(256, bytesNeeded) - (Math.pow(256, bytesNeeded) % range);

  let result;
  do {
    const bytes = crypto.randomBytes(bytesNeeded);
    result = 0;
    for (let i = 0; i < bytesNeeded; i++) {
      result = (result * 256) + bytes[i];
    }
  } while (result >= maxValid);

  return String(result % range).padStart(6, '0');
}

// user_secrets/{uid}/totp/config altında güvenli saklama
async function readUserTotp(uid) {
  const ref = admin.firestore().collection('user_secrets').doc(uid).collection('totp').doc('config');
  const snap = await ref.get();
  if (snap.exists) return snap.data();

  // legacy: users/{uid}.totp
  const legacy = (await admin.firestore().collection('users').doc(uid).get()).data()?.totp;
  return legacy ?? null;
}

async function writeUserTotp(uid, payload) {
  const ref = admin.firestore().collection('user_secrets').doc(uid).collection('totp').doc('config');
  await ref.set({...payload, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
}

async function deleteUserTotpEverywhere(uid) {
  await admin.firestore()
    .collection('user_secrets')
    .doc(uid)
    .collection('totp')
    .doc('config')
    .delete()
    .catch(() => {});
  await admin.firestore()
    .collection('users')
    .doc(uid)
    .set({totp: admin.firestore.FieldValue.delete()}, {merge: true})
    .catch(() => {});
}

export const startEmail2FA = onCall({region: 'europe-west2', cors: true, secrets: [OTP_SALT]}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  const kind = ['login', 'setup', 'disable'].includes(req.data?.type) ? req.data.type : 'login';
  return await startEmail2FAImpl(uid, kind);
});

export const verifyEmail2FA = onCall({region: 'europe-west2', cors: true, secrets: [OTP_SALT]}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  let {code, action} = req.data || {}; // action: 'login' | 'setup' | 'disable'
  code = String(code || '').replace(/\D/g, '');
  if (code.length !== 6) throw new HttpsError('invalid-argument', '6-digit code required.');

  const codeRef = admin.firestore().collection('verification_codes').doc(uid);
  const now = Timestamp.now();

  let remaining = 0;

  const res = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(codeRef);
    if (!snap.exists) return {ok: false, err: 'codeNotFound'};

    const data = snap.data();
    if (!data) return {ok: false, err: 'codeNotFound'};

    if (now.toMillis() > data.expiresAt.toMillis()) {
      tx.delete(codeRef);
      return {ok: false, err: 'codeExpired'};
    }

    if ((data.attempts || 0) >= (data.maxAttempts || 5)) {
      tx.delete(codeRef);
      return {ok: false, err: 'tooManyAttempts'};
    }

    const valid = hmac(code) === data.codeHash;
    if (!valid) {
      const attempts = (data.attempts || 0) + 1;
      remaining = Math.max((data.maxAttempts || 5) - attempts, 0);
      tx.update(codeRef, {attempts});
      return {ok: false, err: 'invalidCodeWithRemaining', remaining};
    }

    // success → consume
    tx.delete(codeRef);
    return {ok: true};
  });

  if (!res.ok) {
    if (res.err === 'invalidCodeWithRemaining') {
      return {success: false, message: 'invalidCodeWithRemaining', remaining};
    }
    return {success: false, message: res.err};
  }

  // On success: stamp
  const usersRef = admin.firestore().collection('users').doc(uid);

  if (action === 'setup') {
    await usersRef.set(
      {
        twoFactorEnabled: true,
        twoFactorEnabledAt: FieldValue.serverTimestamp(),
        lastTwoFactorVerification: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  } else if (action === 'disable') {
    await usersRef.set(
      {
        twoFactorEnabled: false,
        twoFactorDisabledAt: FieldValue.serverTimestamp(),
        lastTwoFactorVerification: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  } else {
    // login default
    await usersRef.set({lastTwoFactorVerification: FieldValue.serverTimestamp()}, {merge: true});
  }

  return {success: true, message: 'verificationSuccess'};
});

export const resendEmail2FA = onCall({region: 'europe-west2', cors: true, secrets: [OTP_SALT]}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  const kind = ['login', 'setup', 'disable'].includes(req.data?.type) ? req.data.type : 'login';
  return await startEmail2FAImpl(uid, kind); // <— .run yerine helper
});

async function startEmail2FAImpl(uid, kind) {
  // startEmail2FA içindeki mevcut gövdeni buraya aynen taşı
  const userRec = await admin.auth().getUser(uid);
  const email = userRec.email;
  if (!email) throw new HttpsError('failed-precondition', 'No email for user.');

  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const language = userDoc.data()?.languageCode || 'en';

  // throttle: 30s
  const codeRef = admin.firestore().collection('verification_codes').doc(uid);
  const last = await codeRef.get();
  if (last.exists) {
    const lastCreated = last.data()?.createdAt?.toDate?.();
    if (lastCreated && Date.now() - lastCreated.getTime() < 30 * 1000) {
      return {success: false, message: 'pleasewait30seconds'};
    }
  }

  const rawCode = secureRandom6();
  const codeHash = hmac(rawCode);
  const nowMs = Date.now();
  const ttlMin = kind === 'login' ? 5 : 10;
  const expiresAt = Timestamp.fromDate(new Date(nowMs + ttlMin * 60 * 1000));

  await admin.firestore().runTransaction(async (tx) => {
    tx.set(
      codeRef,
      {
        codeHash,
        type: kind,
        attempts: 0,
        maxAttempts: 5,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt,
      },
      {merge: true},
    );
  });

  // mail (Firestore Send Email extension veya kendi mail pipeline'ınız)
  const template = getLocalizedTemplate(language, kind);
  template.type = kind;
  const html = generateEmailHTML(template, rawCode);

  await admin.firestore().collection('mail').add({
    to: [email],
    message: {subject: template.subject, html},
    template: {name: 'verification-code', data: {code: rawCode, type: kind, language}},
  });

  return {success: true, sentViaEmail: true, message: 'emailCodeSent'};
}


/**
 * Create secret & otpauth:// URI for setup
 */
export const createTotpSecret = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  
  const existing = await readUserTotp(uid);
  if (existing?.enabled) {
    throw new HttpsError('failed-precondition', 'TOTP already enabled. Disable it first.');
  }

  const userRecord = await admin.auth().getUser(uid);
  const accountName = userRecord.email || uid;

  const secretBase32 = authenticator.generateSecret();
  const otpauth = authenticator.keyuri(accountName, ISSUER, secretBase32);

  await writeUserTotp(uid, {
    enabled: false,
    secretBase32,
    createdAt: FieldValue.serverTimestamp(),
  });

  // legacy alanı temizlemeye bir şans ver (sessiz)
  await admin.firestore().collection('users').doc(uid).set(
    {totp: admin.firestore.FieldValue.delete()},
    {merge: true},
  ).catch(() => {});

  return {success: true, otpauth, secretBase32};
});


export const verifyTotp = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  let {code} = req.data || {};
  code = String(code || '').replace(/\D/g, '');
  if (code.length !== 6) throw new HttpsError('invalid-argument', '6-digit code is required.');

  // rate limit: 5 deneme / 15 dk
  const attemptsRef = admin.firestore().collection('totp_attempts').doc(uid);
  const attemptsSnap = await attemptsRef.get();
  const attempts = attemptsSnap.data()?.attempts || 0;
  const lastAttempt = attemptsSnap.data()?.lastAttempt?.toDate?.();
  if (lastAttempt && Date.now() - lastAttempt.getTime() > 15 * 60 * 1000) {
    await attemptsRef.delete().catch(() => {});
  } else if (attempts >= 5) {
    throw new HttpsError('permission-denied', 'Too many attempts. Try again later.');
  }

  const totp = await readUserTotp(uid);
  if (!totp?.secretBase32) throw new HttpsError('failed-precondition', 'TOTP is not initialized.');

  const isValid = authenticator.check(code, totp.secretBase32, {window: 1});
  if (!isValid) {
    await attemptsRef.set(
      {attempts: attempts + 1, lastAttempt: FieldValue.serverTimestamp()},
      {merge: true},
    );
    throw new HttpsError('permission-denied', 'Invalid TOTP code.');
  }

  await attemptsRef.delete().catch(() => {});

  // Setup ise enable, değilse sadece lastTwoFactorVerification damgası
  const usersRef = admin.firestore().collection('users').doc(uid);
  if (!totp.enabled) {
    await usersRef.set(
      {
        twoFactorEnabled: true,
        twoFactorEnabledAt: FieldValue.serverTimestamp(),
        lastTwoFactorVerification: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    await writeUserTotp(uid, {
      enabled: true,
      secretBase32: totp.secretBase32,
      verifiedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await usersRef.set({lastTwoFactorVerification: FieldValue.serverTimestamp()}, {merge: true});
  }

  return {success: true};
});

export const disableTotp = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;

  // recent-2FA zorunluluğu (5 dk)
  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const last2faTs = userDoc.data()?.lastTwoFactorVerification?.toDate?.();
  if (!last2faTs || Date.now() - last2faTs.getTime() > 5 * 60 * 1000) {
    throw new HttpsError('permission-denied', 'recent-2fa-required');
  }

  await admin.firestore().collection('users').doc(uid).set(
    {
      twoFactorEnabled: false,
      twoFactorDisabledAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await deleteUserTotpEverywhere(uid);

  return {success: true};
});


/**
 * ──────────────────────────────────────────────────────────────────────────────
 * Housekeeping: clean expired verification codes/sessions
 * ──────────────────────────────────────────────────────────────────────────────
 */
export const cleanupExpiredVerificationData = onSchedule(
  {schedule: '0 2 * * *', timeZone: 'Europe/Istanbul', region: 'europe-west3'},
  async () => {
    try {
      const now = Timestamp.now();
      
      const deleteInBatches = async (docs) => {
        const chunks = [];
        for (let i = 0; i < docs.length; i += 450) {
          chunks.push(docs.slice(i, i + 450));
        }
        for (const chunk of chunks) {
          const batch = admin.firestore().batch();
          chunk.forEach((d) => batch.delete(d.ref));
          await batch.commit();
        }
      };

      // Get and delete expired codes
      const expiredCodes = await admin.firestore()
        .collection('verification_codes')
        .where('expiresAt', '<', now)
        .get();
      await deleteInBatches(expiredCodes.docs);

      // Get and delete old attempts
      const oldAttempts = await admin.firestore()
        .collection('totp_attempts')
        .where('lastAttempt', '<', Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)))
        .get();
      await deleteInBatches(oldAttempts.docs);

      return {success: true, totalCleaned: expiredCodes.size + oldAttempts.size};
    } catch (err) {
      console.error('Cleanup error:', err);
      return {success: false};
    }
  },
);

export const hasTotp = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const totp = await readUserTotp(req.auth.uid);
  return {enabled: !!totp?.enabled};
});

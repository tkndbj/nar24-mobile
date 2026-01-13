// functions/15-openai-translation/index.js

import {onRequest} from 'firebase-functions/v2/https';
import {defineSecret} from 'firebase-functions/params';
import {FieldValue} from 'firebase-admin/firestore';
import admin from 'firebase-admin';

// Define secret for OpenAI API key
const openaiApiKey = defineSecret('OPENAI_API_KEY');

// Rate limit configuration
const RATE_LIMIT = {
  maxRequests: 30,
  windowMs: 60 * 1000,
  maxTokensPerDay: 50000,
};

// Validate Firebase ID token
async function verifyAuth(req) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader?.startsWith('Bearer ')) {
    return null;
  }
  
  const idToken = authHeader.split('Bearer ')[1];
  
  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    return decodedToken.uid;
  } catch (error) {
    console.error('Auth verification failed:', error.message);
    return null;
  }
}

// Check and update rate limit
async function checkRateLimit(userId) {
  const now = Date.now();
  const rateLimitRef = admin.firestore().collection('rateLimits').doc(userId);
  
  try {
    const result = await admin.firestore().runTransaction(async (transaction) => {
      const doc = await transaction.get(rateLimitRef);
      const data = doc.data() || {};
      
      const windowStart = data.windowStart || 0;
      let requestCount = data.requestCount || 0;
      
      if (now - windowStart > RATE_LIMIT.windowMs) {
        requestCount = 1;
        transaction.set(rateLimitRef, {
          windowStart: now,
          requestCount: 1,
          dailyTokens: data.dailyTokens || 0,
          dailyReset: data.dailyReset || now,
        }, {merge: true});
      } else if (requestCount >= RATE_LIMIT.maxRequests) {
        return { 
          allowed: false, 
          reason: 'rate_limit', 
          retryAfter: Math.ceil((RATE_LIMIT.windowMs - (now - windowStart)) / 1000), 
        };
      } else {
        transaction.update(rateLimitRef, {
          requestCount: FieldValue.increment(1),
        });
        requestCount++;
      }
      
      const dailyReset = data.dailyReset || 0;
      let dailyTokens = data.dailyTokens || 0;
      
      if (now - dailyReset > 24 * 60 * 60 * 1000) {
        transaction.set(rateLimitRef, {
          dailyTokens: 0,
          dailyReset: now,
        }, {merge: true});
        dailyTokens = 0;
      } else if (dailyTokens >= RATE_LIMIT.maxTokensPerDay) {
        return {allowed: false, reason: 'daily_limit'};
      }
      
      return {allowed: true, dailyTokens};
    });
    
    return result;
  } catch (error) {
    console.error('Rate limit check failed:', error);
    return {allowed: true, dailyTokens: 0};
  }
}

// Update token usage
async function updateTokenUsage(userId, tokensUsed) {
  try {
    await admin.firestore().collection('rateLimits').doc(userId).update({
      dailyTokens: FieldValue.increment(tokensUsed),
    });
  } catch (error) {
    console.error('Failed to update token usage:', error);
  }
}

// Validate input
function validateInput(text, targetLanguage) {
  if (!text || typeof text !== 'string') {
    return {valid: false, error: 'Missing or invalid text'};
  }
  
  if (!targetLanguage || typeof targetLanguage !== 'string') {
    return {valid: false, error: 'Missing or invalid target language'};
  }
  
  const maxLength = 2000;
  if (text.length > maxLength) {
    return {valid: false, error: `Text exceeds maximum length of ${maxLength} characters`};
  }
  
  const validLanguages = ['en', 'tr', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'ar', 'zh', 'ja', 'ko', 'nl', 'pl', 'sv'];
  if (!validLanguages.includes(targetLanguage.toLowerCase())) {
    return {valid: false, error: 'Unsupported target language'};
  }
  
  return {valid: true};
}

// Call OpenAI API
async function translateWithOpenAI(text, targetLanguage, apiKey) {
  const languageNames = {
    en: 'English', tr: 'Turkish', de: 'German', fr: 'French',
    es: 'Spanish', it: 'Italian', pt: 'Portuguese', ru: 'Russian',
    ar: 'Arabic', zh: 'Chinese', ja: 'Japanese', ko: 'Korean',
    nl: 'Dutch', pl: 'Polish', sv: 'Swedish',
  };
  
  const targetLang = languageNames[targetLanguage.toLowerCase()] || targetLanguage;
  
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are a translator. Translate the given text to ${targetLang}. Only respond with the translation, nothing else. Preserve the original formatting and tone.`,
        },
        {
          role: 'user',
          content: text,
        },
      ],
      max_tokens: 1000,
      temperature: 0.3,
    }),
  });
  
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error?.error?.message || `OpenAI API error: ${response.status}`);
  }
  
  const data = await response.json();
  
  return {
    translation: data.choices[0].message.content.trim(),
    tokensUsed: data.usage?.total_tokens || 0,
  };
}

// Single text translation
export const translateText = onRequest(
  {
    region: 'europe-west3',
    secrets: [openaiApiKey],
    cors: true,
    maxInstances: 10,
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({error: 'Method not allowed'});
      return;
    }
    
    const userId = await verifyAuth(req);
    if (!userId) {
      res.status(401).json({error: 'Unauthorized'});
      return;
    }
    
    const rateCheck = await checkRateLimit(userId);
    if (!rateCheck.allowed) {
      const errorResponse = {error: 'Rate limit exceeded'};
      if (rateCheck.retryAfter) {
        res.set('Retry-After', String(rateCheck.retryAfter));
        errorResponse.retryAfter = rateCheck.retryAfter;
      }
      if (rateCheck.reason === 'daily_limit') {
        errorResponse.error = 'Daily translation limit exceeded';
      }
      res.status(429).json(errorResponse);
      return;
    }
    
    const {text, targetLanguage} = req.body;
    const validation = validateInput(text, targetLanguage);
    if (!validation.valid) {
      res.status(400).json({error: validation.error});
      return;
    }
    
    try {
      const result = await translateWithOpenAI(
        text,
        targetLanguage,
        openaiApiKey.value(),
      );
      
      await updateTokenUsage(userId, result.tokensUsed);
      
      res.status(200).json({
        translation: result.translation,
        cached: false,
      });
    } catch (error) {
      console.error('Translation error:', error);
      res.status(500).json({
        error: 'Translation failed',
        message: error.message,
      });
    }
  },
);

// Batch translation
export const translateBatch = onRequest(
  {
    region: 'europe-west3',
    secrets: [openaiApiKey],
    cors: true,
    maxInstances: 5,
    timeoutSeconds: 60,
    memory: '512MiB',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({error: 'Method not allowed'});
      return;
    }
    
    const userId = await verifyAuth(req);
    if (!userId) {
      res.status(401).json({error: 'Unauthorized'});
      return;
    }
    
    const rateCheck = await checkRateLimit(userId);
    if (!rateCheck.allowed) {
      res.status(429).json({error: 'Rate limit exceeded'});
      return;
    }
    
    const {texts, targetLanguage} = req.body;
    
    if (!Array.isArray(texts) || texts.length === 0 || texts.length > 5) {
      res.status(400).json({error: 'texts must be an array of 1-5 items'});
      return;
    }
    
    for (const text of texts) {
      const validation = validateInput(text, targetLanguage);
      if (!validation.valid) {
        res.status(400).json({error: validation.error});
        return;
      }
    }
    
    try {
      const results = await Promise.all(
        texts.map((text) => translateWithOpenAI(text, targetLanguage, openaiApiKey.value())),
      );
      
      const totalTokens = results.reduce((sum, r) => sum + r.tokensUsed, 0);
      await updateTokenUsage(userId, totalTokens);
      
      res.status(200).json({
        translations: results.map((r) => r.translation),
      });
    } catch (error) {
      console.error('Batch translation error:', error);
      res.status(500).json({error: 'Translation failed'});
    }
  },
);

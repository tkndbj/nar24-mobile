/**
 * createScannedRestaurantOrder — restaurant scans a paper receipt, this CF
 * creates an `orders-food` doc from the OCR'd data so the order can flow
 * through the standard delivery pipeline.
 *
 * Behavior parity with the in-app accept flow:
 *   • Order is born `status: 'accepted'` with `courierType: 'ours'` so the
 *     auto-assigner (CF-54) picks it up immediately. Restaurant scanned a
 *     paper receipt → intent is "Nar24 delivers."
 *   • `fees` snapshot is frozen at creation (commissionRate + shipmentFeeRate
 *     read from the restaurant doc), matching CF-27's buildFeesSnapshot. Keeps
 *     scanned orders in the same accounting bucket (`courierType: 'ours'`,
 *     not `legacy`) and contributes to platformRevenue.
 *   • `acceptedAt` is stamped so the auto-assigner's "dispatchable since"
 *     window applies cleanly.
 *
 * Everything else that used to live in this module (FCM topic broadcasts,
 * "Inform Courier" heads-up, courier-call requests, the food_couriers topic
 * push and its scheduled cleanups) has been removed. Auto-assignment (CF-54)
 * now dispatches orders directly and CF-40 → CF-46 handles per-courier in-app
 * notifications, so the broadcast pool is no longer needed.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import admin from 'firebase-admin';

const REGION = 'europe-west3';
const RATES_VERSION = 1;

const anthropicApiKey = defineSecret('ANTHROPIC_API_KEY');

function money(n) {
  return Math.round(n * 100) / 100;
}

// Mirrors CF-27 buildFeesSnapshot. Kept in sync intentionally — if the
// formula changes there, update here too.
function buildFeesSnapshot({ subtotal, commissionRate, shipmentFeeRate, courierType }) {
  const safeSubtotal = Math.max(0, Number(subtotal) || 0);
  const safeCommissionRate = Math.max(0, Number(commissionRate) || 0);
  const safeShipmentFeeRate = Math.max(0, Number(shipmentFeeRate) || 0);

  const commissionAmount = money((safeSubtotal * safeCommissionRate) / 100);
  const shipmentFeeApplied = courierType === 'ours' ? money(safeShipmentFeeRate) : 0;

  const platformRevenue = money(commissionAmount + shipmentFeeApplied);
  const restaurantPayout = money(
    safeSubtotal - commissionAmount - shipmentFeeApplied,
  );

  return {
    subtotal: money(safeSubtotal),
    commissionRate: safeCommissionRate,
    shipmentFeeRate: money(safeShipmentFeeRate),
    courierType,
    commissionAmount,
    shipmentFeeApplied,
    platformRevenue,
    restaurantPayout,
    status: 'finalized',
    calculatedAt: admin.firestore.Timestamp.now(),
    ratesVersion: RATES_VERSION,
  };
}

export const createScannedRestaurantOrder = onCall(
  { region: REGION, memory: '512MiB', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');

    const {
      restaurantId,
      scannedRawText = '',
      detectedAddress = null,
      detectedTotal = null,
      detectedPhone = null,
      detectedLat = null,
      detectedLng = null,
      detectedItems = [],
    } = request.data;

    if (!restaurantId) throw new HttpsError('invalid-argument', 'restaurantId is required.');

    const db = admin.firestore();
    const uid = request.auth.uid;

    // Verify caller belongs to this restaurant
    const userRecord = await admin.auth().getUser(uid);
    const restaurantClaims = userRecord.customClaims?.restaurants || {};
    if (!(restaurantId in restaurantClaims)) {
      throw new HttpsError('permission-denied', 'Not authorised for this restaurant.');
    }

    const restaurantSnap = await db.collection('restaurants').doc(restaurantId).get();
    if (!restaurantSnap.exists) throw new HttpsError('not-found', 'Restaurant not found.');
    const restaurant = restaurantSnap.data();

    const locationGeoPoint = (
      typeof detectedLat === 'number' && typeof detectedLng === 'number'
    ) ? new admin.firestore.GeoPoint(detectedLat, detectedLng) : null;

    const orderRef = db.collection('orders-food').doc();
    const orderId = orderRef.id;

    // Freeze fees snapshot using the restaurant's current rates, same shape
    // CF-27 produces on the pending → accepted transition for in-app orders.
    const subtotal = typeof detectedTotal === 'number' ? detectedTotal : 0;
    const commissionRate  = Number(restaurant.ourComission)   || 0;
    const shipmentFeeRate = Number(restaurant.ourShipmentFee) || 0;
    const fees = buildFeesSnapshot({
      subtotal,
      commissionRate,
      shipmentFeeRate,
      courierType: 'ours',
    });

    await orderRef.set({
      sourceType: 'scanned_receipt',
      restaurantId,
      restaurantName: restaurant.name || '',
      restaurantProfileImage: restaurant.profileImageUrl || '',
      restaurantOwnerId: restaurant.ownerId || '',
      restaurantPhone: restaurant.contactNo || '',
      restaurantLat: restaurant.latitude || null,
      restaurantLng: restaurant.longitude || null,

      // Auto-dispatch path. CF-54's trigger fires on pending → accepted, but
      // scanned orders are born accepted, so the trigger won't see a
      // transition. The retry sweep (every ~30-90s) catches it via the
      // status='accepted' + courierType='ours' + cargoUserId=null filter.
      courierType: 'ours',
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      fees,
      // Denormalized for area analytics (CF-55). Restaurant doc uses
      // `city` for the broader district and `subcity` for the neighborhood,
      // matching buyer's deliveryAddress.mainRegion + .city respectively.
      restaurantCity: restaurant.city || '',
      restaurantSubcity: restaurant.subcity || '',

      // No courier yet — assigned when courier takes from pool
      cargoUserId: null,
      cargoName: null,

      buyerId: null,
      buyerName: 'External Customer',
      buyerPhone: detectedPhone || '',

      // Items from OCR
      items: Array.isArray(detectedItems) ? detectedItems.slice(0, 50).map((item, i) => ({
        foodId: `scanned_${i}`,
        name: typeof item.name === 'string' ? item.name.substring(0, 200) : 'Unknown item',
        quantity: typeof item.quantity === 'number' && item.quantity > 0 ? Math.floor(item.quantity) : 1,
        price: typeof item.price === 'number' ? item.price : 0,
        extras: [],
        specialNotes: '',
        itemTotal: (typeof item.price === 'number' ? item.price : 0) * (typeof item.quantity === 'number' && item.quantity > 0 ? Math.floor(item.quantity) : 1),
      })) : [],
      itemCount: Array.isArray(detectedItems) ? detectedItems.reduce((sum, item) => sum + (typeof item.quantity === 'number' && item.quantity > 0 ? Math.floor(item.quantity) : 1), 0) : 0,

      subtotal,
      deliveryFee: 0,
      totalPrice: subtotal,
      currency: 'TL',

      paymentMethod: 'unknown',
      isPaid: false,

      deliveryType: 'delivery',
      deliveryAddress: detectedAddress ? {
        addressLine1: detectedAddress,
        city: '',
        phoneNumber: detectedPhone || '',
        location: locationGeoPoint,
      } : null,

      scannedReceipt: {
        rawText: scannedRawText.substring(0, 2000),
        detectedAddress: detectedAddress || null,
        detectedTotal: typeof detectedTotal === 'number' ? detectedTotal : null,
        scannedAt: new Date().toISOString(),
      },

      // Starts as accepted — restaurant will mark ready, then courier takes it
      status: 'accepted',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      needsReview: false,
      orderNotes: '',
      estimatedPrepTime: 0,
    });

    console.log(`[ScannedOrder] Restaurant ${restaurantId} created scanned order ${orderId}`);
    return { success: true, orderId };
  }
);

// ============================================================================
// parseReceiptText — calls Claude Haiku to extract structured fields from
// raw OCR'd receipt text. Lives server-side so the Anthropic API key isn't
// shipped in the app binary, and so scan results show up in CF logs.
// ============================================================================

const buildPrompt = (rawText) => `Extract delivery information from this receipt OCR text.
The text may contain OCR errors (garbled characters, broken numbers, etc).
Reply ONLY with a valid JSON object — no explanation, no markdown fences.

{
  "total": <grand total as a number, null if not found>,
  "address": "<full delivery address, null if not found>",
  "phone": "<customer phone number, null if not found>",
  "order_id": "<order or receipt number, null if not found>",
  "items": [
    {"name": "<item name>", "quantity": <number>, "price": <unit price as number>}
  ]
}

Rules:
- total: find the FINAL amount the customer pays after any discounts. Rules in order:
  1. NEVER return "Ara Toplam" (subtotal).
  2. If a discount percentage is mentioned (e.g. %15 indirim), the final total is LESS than the ara toplam — look for the smaller number after the discount line.
  3. On YemekSepeti receipts the numbers appear in this order on one line: [ara toplam] [toplam] [kdv] — so if you see a sequence of numbers, the SECOND main amount is the final total, not the first.
  4. Fix garbled digits like 250,7: → 250.75, 295,0( → 295.00. Integer-only totals (e.g. "430") are fine — return as plain number.
  Return as a plain number with no currency symbol.
- address: look for street names, district, city, postal code. In North Cyprus receipts look for KKTC, Kuzey Kıbrıs, Lefkoşa, Gazimağusa, Girne, İskele, KYK, yurdu, üniversite, DAÜ, GAÜ, NEU. Return the full address on one line.
- phone: look for TEL, telefon, GSM patterns. Include + prefix if present.
- order_id: look for sipariş no, order no, receipt no, # prefixed codes.
- items: extract each food/drink item with its name, quantity, and unit price. Skip non-food lines like delivery fee, discount, tax, subtotal, total. If quantity is not shown, assume 1. Fix OCR errors in names. Return empty array if no items found.

Receipt OCR text:
${rawText.length > 1500 ? rawText.substring(0, 1500) : rawText}`;

export const parseReceiptText = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    secrets: [anthropicApiKey],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');

    const { rawText } = request.data || {};
    if (!rawText || typeof rawText !== 'string') {
      throw new HttpsError('invalid-argument', 'rawText is required.');
    }
    if (rawText.length < 20) {
      // OCR produced nothing usable — caller can fall back to regex
      return { total: null, address: null, phone: null, order_id: null, items: [] };
    }

    let response;
    try {
      response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': anthropicApiKey.value(),
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 1024,
          messages: [{ role: 'user', content: buildPrompt(rawText) }],
        }),
        signal: AbortSignal.timeout(20000),
      });
    } catch (err) {
      console.error('[parseReceiptText] Anthropic fetch failed:', err.message);
      throw new HttpsError('unavailable', 'Receipt parser unavailable.');
    }

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      console.error(`[parseReceiptText] Anthropic ${response.status}: ${body.slice(0, 500)}`);
      throw new HttpsError('internal', `Anthropic API error ${response.status}.`);
    }

    const data = await response.json();
    const content = data?.content?.[0]?.text;
    if (!content) {
      console.error('[parseReceiptText] Empty content from Anthropic:', JSON.stringify(data).slice(0, 500));
      throw new HttpsError('internal', 'Empty response from parser.');
    }

    // Strip markdown fences if model added them despite instructions
    const clean = content.replaceAll('```json', '').replaceAll('```', '').trim();

    let parsed;
    try {
      parsed = JSON.parse(clean);
    } catch (err) {
      console.error('[parseReceiptText] JSON parse failed:', err.message, 'content:', clean.slice(0, 500));
      throw new HttpsError('internal', 'Could not parse receipt response.');
    }

    console.log(`[parseReceiptText] uid=${request.auth.uid} extracted total=${parsed.total} items=${(parsed.items || []).length} address=${(parsed.address || '').length}c`);
    return {
      total: typeof parsed.total === 'number' ? parsed.total : null,
      address: typeof parsed.address === 'string' ? parsed.address : null,
      phone: typeof parsed.phone === 'string' ? parsed.phone : null,
      order_id: typeof parsed.order_id === 'string' ? parsed.order_id : null,
      items: Array.isArray(parsed.items) ? parsed.items.slice(0, 50) : [],
    };
  }
);

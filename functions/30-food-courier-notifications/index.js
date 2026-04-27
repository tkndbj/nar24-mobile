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
const googleMapsKey   = defineSecret('GOOGLE_MAPS_GEOCODING_KEY');

// Accept these Google Geocoding precision levels — `APPROXIMATE` is rejected
// because it usually means Google only matched at city level, which is
// useless for couriers.
const ACCEPTABLE_LOCATION_TYPES = new Set([
  'ROOFTOP',
  'RANGE_INTERPOLATED',
  'GEOMETRIC_CENTER',
]);

// Pull lat/lng straight from a URL string. Covers `geo:`, `?q=`, `@lat,lng`
// patterns produced by Google Maps short-link landing pages.
function tryExtractCoordsFromUrl(raw) {
  if (!raw) return null;

  const geoMatch = raw.match(/geo:(-?\d+\.?\d*),(-?\d+\.?\d*)/);
  if (geoMatch) {
    const lat = parseFloat(geoMatch[1]);
    const lng = parseFloat(geoMatch[2]);
    if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
  }

  const qMatch = raw.match(/[?&]q=(?:loc:)?(-?\d+\.?\d*),(-?\d+\.?\d*)/);
  if (qMatch) {
    const lat = parseFloat(qMatch[1]);
    const lng = parseFloat(qMatch[2]);
    if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
  }

  const atMatch = raw.match(/@(-?\d+\.\d{3,}),(-?\d+\.\d{3,})/);
  if (atMatch) {
    const lat = parseFloat(atMatch[1]);
    const lng = parseFloat(atMatch[2]);
    if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
  }

  return null;
}

// Resolve a QR URL to coordinates. Tries direct extraction first, then
// follows redirects (Cloud Functions egress is unrestricted, unlike a
// mobile app). Falls back to scanning the final HTML body for og:url /
// canonical / inline @lat,lng patterns. Returns { lat, lng, source } or null.
async function resolveQrToCoords(qrUrl) {
  const direct = tryExtractCoordsFromUrl(qrUrl);
  if (direct) return { ...direct, source: 'qr_direct' };

  // Only follow links that look like Google Maps short links; avoids
  // following arbitrary URLs from a malicious receipt QR.
  const isMapsShortLink =
    /^https?:\/\/(maps\.app\.goo\.gl|goo\.gl\/maps|maps\.google\.com)/i.test(qrUrl);
  if (!isMapsShortLink) return null;

  let currentUrl = qrUrl;
  for (let hop = 0; hop < 5; hop++) {
    let response;
    try {
      response = await fetch(currentUrl, {
        method: 'GET',
        redirect: 'manual',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
          'Accept-Language': 'tr-TR,tr;q=0.9,en;q=0.8',
        },
        signal: AbortSignal.timeout(8000),
      });
    } catch (err) {
      console.warn(`[resolveQrToCoords] Hop ${hop} fetch failed:`, err.message);
      return null;
    }

    const location = response.headers.get('location');
    if (location) {
      const fromLoc = tryExtractCoordsFromUrl(location);
      if (fromLoc) return { ...fromLoc, source: `qr_redirect_hop${hop}` };
      currentUrl = new URL(location, currentUrl).toString();
      continue;
    }

    // No Location header — final page reached. Look at the body.
    const body = await response.text().catch(() => '');
    const scope = body.length > 100000 ? body.substring(0, 100000) : body;

    const og = scope.match(/<meta[^>]*property=["']og:url["'][^>]*content=["']([^"']+)["']/i);
    if (og) {
      const fromOg = tryExtractCoordsFromUrl(og[1]);
      if (fromOg) return { ...fromOg, source: 'qr_body_og' };
    }
    const canonical = scope.match(/<link[^>]*rel=["']canonical["'][^>]*href=["']([^"']+)["']/i);
    if (canonical) {
      const fromCan = tryExtractCoordsFromUrl(canonical[1]);
      if (fromCan) return { ...fromCan, source: 'qr_body_canonical' };
    }
    const inline = scope.match(/@(-?\d{1,2}\.\d{4,}),(-?\d{1,3}\.\d{4,})/);
    if (inline) {
      const lat = parseFloat(inline[1]);
      const lng = parseFloat(inline[2]);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        return { lat, lng, source: 'qr_body_inline' };
      }
    }
    return null;
  }
  return null;
}

// Geocode a free-text address. Returns { lat, lng, locationType, formatted }
// on success, or null on any failure (no result, API error, low precision).
// `biasLat`/`biasLng` shift Google's interpretation toward a region — pass
// the restaurant's coordinates so KKTC addresses don't get matched against
// mainland Cyprus.
async function geocodeAddress({ address, biasLat, biasLng, apiKey }) {
  if (!address || typeof address !== 'string' || !apiKey) return null;

  const params = new URLSearchParams({
    address,
    key: apiKey,
    region: 'cy', // Cyprus regional code (covers both halves)
    language: 'tr',
  });

  // Bias the search to a 25 km box around the restaurant. Strong locality
  // hint without forbidding results outside the box (Google still returns
  // them, just with lower priority).
  if (typeof biasLat === 'number' && typeof biasLng === 'number') {
    const dLat = 0.225; // ~25 km in latitude
    const dLng = 0.275; // ~25 km in longitude at this latitude
    params.set(
      'bounds',
      `${biasLat - dLat},${biasLng - dLng}|${biasLat + dLat},${biasLng + dLng}`,
    );
  }

  let response;
  try {
    response = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`,
      { signal: AbortSignal.timeout(8000) },
    );
  } catch (err) {
    console.error('[geocodeAddress] Fetch failed:', err.message);
    return null;
  }

  if (!response.ok) {
    console.error(`[geocodeAddress] HTTP ${response.status}`);
    return null;
  }

  const data = await response.json().catch(() => null);
  if (!data || data.status !== 'OK' || !Array.isArray(data.results) || data.results.length === 0) {
    console.warn(`[geocodeAddress] No result. status=${data?.status} address="${address}"`);
    return null;
  }

  const top = data.results[0];
  const locationType = top.geometry?.location_type;
  if (!ACCEPTABLE_LOCATION_TYPES.has(locationType)) {
    console.warn(`[geocodeAddress] Rejected low-precision result. location_type=${locationType} address="${address}"`);
    return null;
  }

  const lat = top.geometry?.location?.lat;
  const lng = top.geometry?.location?.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;

  return {
    lat,
    lng,
    locationType,
    formatted: top.formatted_address || address,
  };
}

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
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 30,
    secrets: [googleMapsKey],
  },
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
      detectedQrUrls = [],
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

    // Resolve a GeoPoint for the delivery address. Priority:
    //   1. Client-supplied lat/lng (e.g. client already followed a QR redirect)
    //   2. Server-side QR resolution — receipt QRs printed by paper-receipt
    //      vendors point to a Google Maps short link; we follow it server-
    //      side because Cloud Functions has unrestricted egress and Google's
    //      landing page exposes coords via og:url / canonical / inline.
    //   3. Address geocoding — the long shot for KKTC, where many streets
    //      aren't in Google's index at all.
    //   4. null — courier sees the address text only.
    let resolvedLocation = locationGeoPoint;
    let qrResolution = null;
    let geocodeResult = null;

    if (!resolvedLocation && Array.isArray(detectedQrUrls) && detectedQrUrls.length > 0) {
      for (const qrUrl of detectedQrUrls) {
        if (typeof qrUrl !== 'string' || qrUrl.length === 0) continue;
        try {
          const resolved = await resolveQrToCoords(qrUrl);
          if (resolved) {
            qrResolution = { url: qrUrl, ...resolved };
            resolvedLocation = new admin.firestore.GeoPoint(resolved.lat, resolved.lng);
            console.log(`[ScannedOrder] QR resolved → ${resolved.lat},${resolved.lng} (${resolved.source}) url=${qrUrl}`);
            break;
          } else {
            console.warn(`[ScannedOrder] QR could not be resolved: ${qrUrl}`);
          }
        } catch (err) {
          console.error(`[ScannedOrder] QR resolution error for ${qrUrl}:`, err.message);
        }
      }
    }

    if (!resolvedLocation && detectedAddress) {
      geocodeResult = await geocodeAddress({
        address: detectedAddress,
        biasLat: typeof restaurant.latitude  === 'number' ? restaurant.latitude  : null,
        biasLng: typeof restaurant.longitude === 'number' ? restaurant.longitude : null,
        apiKey: googleMapsKey.value(),
      });
      if (geocodeResult) {
        resolvedLocation = new admin.firestore.GeoPoint(geocodeResult.lat, geocodeResult.lng);
        console.log(`[ScannedOrder] Geocoded "${detectedAddress}" → ${geocodeResult.lat},${geocodeResult.lng} (${geocodeResult.locationType})`);
      }
    }

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
        location: resolvedLocation,
      } : null,

      scannedReceipt: {
        rawText: scannedRawText.substring(0, 2000),
        detectedAddress: detectedAddress || null,
        detectedTotal: typeof detectedTotal === 'number' ? detectedTotal : null,
        // Full diagnostic trail for the location resolution path — lets
        // admins see exactly which fallback fired (or why none did).
        detectedQrUrls: Array.isArray(detectedQrUrls) ?
          detectedQrUrls.filter((u) => typeof u === 'string').slice(0, 10) :
          [],
        qrResolution: qrResolution || null,
        geocode: geocodeResult ? {
          lat: geocodeResult.lat,
          lng: geocodeResult.lng,
          locationType: geocodeResult.locationType,
          formattedAddress: geocodeResult.formatted,
        } : null,
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
- address: return ONLY the geocodable street address. Critical rules:
  1. DO NOT include the customer's name. Names appear right before the address (e.g. "Deniz Dilşa Okuryazar Nehir Sokak..." → drop "Deniz Dilşa Okuryazar"). A name is anything that looks like First+Last (1-3 capitalised words) preceding the street.
  2. DO NOT include unit-level details that confuse geocoders: skip "Kat 1" (floor), "Daire 4" (apartment), "Apt 2", "No: 5". Keep only the building number when it's clearly a street number.
  3. Start with the street name (cadde / sokak / bulvarı). If there are TWO consecutive street-like phrases (e.g. "Necmettin Erbakan Nehir Sokak"), they're a parent road + side street — keep only the SECOND, more specific one ("Nehir Sokak").
  4. End with "Gazimağusa, KKTC" or "Lefkoşa, KKTC" / "Girne, KKTC" / "İskele, KKTC" — drop duplicated city tokens and full country names like "Kuzey Kıbrıs Türk Cumhuriyeti", abbreviate to "KKTC".
  5. North Cyprus context: look for KKTC, Kuzey Kıbrıs, Lefkoşa, Gazimağusa, Girne, İskele, KYK, yurdu, üniversite, DAÜ, GAÜ, NEU.
  Return the cleaned address on one line.
- phone: look for TEL, telefon, GSM patterns. Include + prefix if present.
- order_id: look for sipariş no, order no, receipt no, # prefixed codes.
- items: extract every food/drink line you can identify. This is the most important field — be GENEROUS, not conservative.
  1. Receipt OCR often splits item names from their prices: names appear in one block (sometimes preceded by a quantity like "1 Su (50 cl)" or "2 Pizza"), prices appear later in a column (e.g. "B 50  b380  B 430"). Match them by position when possible — first item gets first price, second item gets second price, etc.
  2. Quantity rules: if the line starts with a small integer (1, 2, 3) treat it as quantity. Otherwise default quantity to 1.
  3. Price rules: pull the per-line price from the price block in the same position. If a price is unreadable or missing, return price: 0 — DO NOT drop the item.
  4. Names: clean up obvious OCR garbage (Çlkolatalı → Çikolatalı, Belçlka → Belçika, çllek → çilek). Keep parentheticals (e.g. "(50 cl)", "Muz,çilek").
  5. Skip ONLY these non-item lines: delivery fee, ara toplam, toplam, KDV, tax, discount/indirim, ödenecek tutar, sipariş no, tarih.
  6. Common Turkish/English food terms to recognise: pizza, burger, döner, kebap, lahmacun, pide, köfte, salata, çorba, börek, mantı, makarna, tavuk, balık, et, su, ayran, kola, çay, kahve, waffle, dondurma, tatlı.
  7. Return empty array ONLY if you genuinely see no food/drink names in the OCR — not just because prices are messy.

Receipt OCR text:
${rawText.length > 1500 ? rawText.substring(0, 1500) : rawText}`;

export const parseReceiptText = onCall(
  {
    region: REGION,
    memory: '512MiB',
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

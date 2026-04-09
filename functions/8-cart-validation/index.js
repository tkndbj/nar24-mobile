// functions/8-cart-validation/index.js

import admin from 'firebase-admin';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {checkRateLimit} from '../shared/redis.js';

// ============================================================================
// HELPER FUNCTIONS - Define once, reuse everywhere
// ============================================================================

const safeNumber = (value, defaultValue = 0) => {
  if (value === null || value === undefined || isNaN(value)) {
    return defaultValue;
  }
  return Number(value);
};

const safePrice = (value) => {
  const num = safeNumber(value, 0);
  return num.toFixed(2);
};

const hasChanged = (cachedValue, currentValue) => {
  // If cached value is undefined, we never cached it - no change detection
  if (cachedValue === undefined) return false;
  
  // Both null/undefined - no change
  if (cachedValue == null && currentValue == null) return false;
  
  // One is null, other isn't - changed
  if ((cachedValue == null) !== (currentValue == null)) return true;
  
  // Both have values - compare them
  return cachedValue !== currentValue;
};

const hasPriceChanged = (cachedPrice, currentPrice, tolerance = 0.01) => {
  // If cached price is undefined, we never cached it
  if (cachedPrice === undefined) return false;
  
  const cached = safeNumber(cachedPrice);
  const current = safeNumber(currentPrice);
  
  return Math.abs(cached - current) > tolerance;
};

// ============================================================================
// VALIDATE CART CHECKOUT
// ============================================================================

export const validateCartCheckout = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 120,
    memory: '1GiB',
    concurrency: 80,
    maxInstances: 200,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    const startTime = Date.now();
    
    // ============================================================
    // 1. AUTHENTICATION & RATE LIMITING
    // ============================================================
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = request.auth.uid;

    // Rate limit: 30 requests per 60 seconds per user
    const withinLimit = await checkRateLimit(`validation_rate:${userId}`, 30, 60);
    if (!withinLimit) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many validation requests. Please wait a moment.',
      );
    }

    // ============================================================
    // 2. INPUT VALIDATION
    // ============================================================
    const {cartItems, reserveStock = false} = request.data;
    
    if (!Array.isArray(cartItems) || cartItems.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'cartItems must be a non-empty array',
      );
    }

    if (cartItems.length > 500) {
      throw new HttpsError(
        'invalid-argument',
        'Cannot validate more than 500 items at once',
      );
    }

    // Validate cart item structure
    for (const item of cartItems) {
      if (!item.productId || typeof item.productId !== 'string') {
        throw new HttpsError(
          'invalid-argument',
          'Each cart item must have a valid productId',
        );
      }
      if (!item.quantity || typeof item.quantity !== 'number' || item.quantity < 1) {
        throw new HttpsError(
          'invalid-argument',
          'Each cart item must have a valid quantity >= 1',
        );
      }
    }

    console.log(`🔍 Validating ${cartItems.length} items for user ${userId}`);

    // ============================================================
    // 3. PARALLEL BATCH FETCHING
    // ============================================================
    const validationResults = {
      isValid: true,
      errors: {},
      warnings: {},
      validatedItems: [],
      totalPrice: 0,
      currency: 'TL',
    };

    const productMap = new Map();

    const itemsBySource = { 'shop_products': [], 'products': [] };
    for (const item of cartItems) {
      const source = item.productSource || 'shop_products';
      if (!itemsBySource[source]) itemsBySource[source] = [];
      itemsBySource[source].push(item.productId);
    }
    
    const fetchFromCollection = async (collection, ids) => {
      if (ids.length === 0) return [];
      const batches = [];
      for (let i = 0; i < ids.length; i += 10) {
        batches.push(ids.slice(i, i + 10));
      }
      const snapshots = await Promise.all(
        batches.map((batch) =>
          admin.firestore()
            .collection(collection)
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get()
        )
      );
      return snapshots.flatMap((snap) =>
        snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
      );
    };
    
    const [shopProducts, userProducts] = await Promise.all([
      fetchFromCollection('shop_products', itemsBySource['shop_products']),
      fetchFromCollection('products', itemsBySource['products']),
    ]);
    
    [...shopProducts, ...userProducts].forEach((product) => {
      productMap.set(product.id, product);
    });
    
    console.log(`📦 Fetched ${productMap.size} products (shop_products: ${itemsBySource['shop_products'].length}, products: ${itemsBySource['products'].length})`);

    // ============================================================
    // 4. VALIDATE EACH CART ITEM
    // ============================================================
    for (const cartItem of cartItems) {
      const {productId, quantity, selectedColor} = cartItem;
      const product = productMap.get(productId);

      // ✅ EXTRACT CACHED VALUES WITH SAFE DEFAULTS
      const cachedPrice = cartItem.cachedPrice; // Keep as-is (may be undefined)
      const cachedBundlePrice = cartItem.cachedBundlePrice;      
      const cachedDiscountPercentage = cartItem.cachedDiscountPercentage;
      const cachedDiscountThreshold = cartItem.cachedDiscountThreshold;
      const cachedBulkDiscountPercentage = cartItem.cachedBulkDiscountPercentage;
      const cachedMaxQuantity = cartItem.cachedMaxQuantity;

      // Check 1: Product exists
      if (!product) {
        validationResults.errors[productId] = {
          key: 'product_not_available',
          params: {},
        };
        validationResults.isValid = false;
        continue;
      }

      // Check 2: Product not paused
      if (product.paused === true) {
        validationResults.errors[productId] = {
          key: 'product_unavailable',
          params: {},
        };
        validationResults.isValid = false;
        continue;
      }

      // Check 3: Stock availability
      let availableStock = 0;

      if (selectedColor && product.colorQuantities && 
          product.colorQuantities[selectedColor] !== undefined) {
        availableStock = safeNumber(product.colorQuantities[selectedColor]);
      } else {
        availableStock = safeNumber(product.quantity);
      }

      if (availableStock <= 0) {
        validationResults.errors[productId] = {
          key: 'out_of_stock',
          params: {},
        };
        validationResults.isValid = false;
        continue;
      }

      if (quantity > availableStock) {
        validationResults.errors[productId] = {
          key: 'insufficient_stock',
          params: {
            available: availableStock,
            requested: quantity,
          },
        };
        validationResults.isValid = false;
        continue;
      }

      // Check 4: Max quantity limit
      if (product.maxQuantity && quantity > product.maxQuantity) {
        validationResults.errors[productId] = {
          key: 'max_quantity_exceeded',
          params: {
            maxQuantity: product.maxQuantity,
          },
        };
        validationResults.isValid = false;
        continue;
      }

      // ============================================================
      // PRICE & PREFERENCE VALIDATION (WARNINGS)
      // ============================================================

      // ✅ Check 5: Base price changes (SAFE)
      if (hasPriceChanged(cachedPrice, product.price)) {
        validationResults.warnings[productId] = {
          key: 'price_changed',
          params: {
            currency: product.currency || 'TL',
            oldPrice: safePrice(cachedPrice),
            newPrice: safePrice(product.price),
          },
        };
      }

// ✅ Extract current bundle price from product's bundleData
let currentBundlePrice = null;
if (product.bundleData && Array.isArray(product.bundleData) && product.bundleData.length > 0) {
  currentBundlePrice = product.bundleData[0].bundlePrice;
}

// ✅ Check 6: Bundle availability & price changes (IMPROVED)
if (cachedBundlePrice !== undefined && cachedBundlePrice !== null && cachedBundlePrice > 0) {
  // User HAD bundle pricing when they added to cart
  
  if (currentBundlePrice === null || currentBundlePrice === undefined || currentBundlePrice <= 0) {
    // ✅ BUNDLE NO LONGER AVAILABLE
    // Happens when: bundle deleted, product removed from bundle, or bundle deactivated
    validationResults.warnings[productId] = {
      key: 'bundle_no_longer_available',
      params: {
        currency: product.currency || 'TL',
        bundlePrice: safePrice(cachedBundlePrice),
        regularPrice: safePrice(product.price),
      },
    };
  } else if (hasPriceChanged(cachedBundlePrice, currentBundlePrice)) {
    // ✅ BUNDLE PRICE CHANGED (price updated but bundle still exists)
    validationResults.warnings[productId] = {
      key: 'bundle_price_changed',
      params: {
        currency: product.currency || 'TL',
        oldPrice: safePrice(cachedBundlePrice),
        newPrice: safePrice(currentBundlePrice),
      },
    };
  }
}

      // ✅ Check 7: Discount percentage changes (SAFE)
      if (hasChanged(cachedDiscountPercentage, product.discountPercentage)) {
        validationResults.warnings[productId] = {
          key: 'discount_updated',
          params: {
            oldDiscount: safeNumber(cachedDiscountPercentage),
            newDiscount: safeNumber(product.discountPercentage),
          },
        };
      }

      // ✅ Check 8: Discount threshold changes (SAFE)
      if (hasChanged(cachedDiscountThreshold, product.discountThreshold)) {
        validationResults.warnings[productId] = {
          key: 'discount_threshold_changed',
          params: {
            oldThreshold: safeNumber(cachedDiscountThreshold),
            newThreshold: safeNumber(product.discountThreshold),
          },
        };
      }

      // ✅ Check 9: Bulk discount percentage changes (SAFE)
      if (hasChanged(cachedBulkDiscountPercentage, product.bulkDiscountPercentage)) {
        validationResults.warnings[productId] = {
          key: 'bulk_discount_changed',
          params: {
            oldDiscount: safeNumber(cachedBulkDiscountPercentage),
            newDiscount: safeNumber(product.bulkDiscountPercentage),
          },
        };
      }

      // ✅ Check 10: Max quantity reduction (SAFE - only warn if it got SMALLER)
      if (cachedMaxQuantity !== undefined &&
          product.maxQuantity !== undefined &&
          product.maxQuantity !== null &&
          product.maxQuantity < cachedMaxQuantity) {
        validationResults.warnings[productId] = {
          key: 'max_quantity_reduced',
          params: {
            oldMax: safeNumber(cachedMaxQuantity),
            newMax: safeNumber(product.maxQuantity),
          },
        };
      }

      // ============================================================
      // CALCULATE FINAL PRICE (WITH DISCOUNTS)
      // ============================================================
      
      let finalUnitPrice = safeNumber(product.price);
      
      // Apply bulk discount if applicable
      if (product.discountThreshold && product.bulkDiscountPercentage) {
        if (quantity >= product.discountThreshold) {
          finalUnitPrice = finalUnitPrice * (1 - product.bulkDiscountPercentage / 100);
        }
      }

      const itemTotal = finalUnitPrice * quantity;

      // ✅ Get color image safely
      let colorImage = null;
      if (selectedColor && product.colorImages && 
          product.colorImages[selectedColor] && 
          Array.isArray(product.colorImages[selectedColor]) &&
          product.colorImages[selectedColor].length > 0) {
        colorImage = product.colorImages[selectedColor][0];
      }

      // ✅ Add validated item with all details
      validationResults.validatedItems.push({
        productId,
        quantity,
        availableStock,
        unitPrice: finalUnitPrice,
        total: itemTotal,
        currency: product.currency || 'TL',
        productName: product.productName || 'Unknown Product',
        imageUrl: (product.imageUrls && product.imageUrls.length > 0) ? 
          product.imageUrls[0] : '',
        selectedColor: selectedColor || null,
        colorImage: colorImage,
        
        // ✅ Include sale preferences (with safe defaults)
        discountPercentage: product.discountPercentage ?? null,
        discountThreshold: product.discountThreshold ?? null,
        bulkDiscountPercentage: product.bulkDiscountPercentage ?? null,
        maxQuantity: product.maxQuantity ?? null,
        bundlePrice: currentBundlePrice ?? null, // ✅ FIX: Use currentBundlePrice, not product.bundlePrice
      });

      validationResults.totalPrice += itemTotal;
      validationResults.currency = product.currency || 'TL';
    }

    // ============================================================
    // 5. ATOMIC STOCK RESERVATION
    // ============================================================
    if (reserveStock && validationResults.isValid) {
      console.log('🔒 Attempting atomic stock reservation...');
      
      try {
        const TRANSACTION_CHUNK_SIZE = 100;
        
        for (let i = 0; i < cartItems.length; i += TRANSACTION_CHUNK_SIZE) {
          const chunk = cartItems.slice(i, i + TRANSACTION_CHUNK_SIZE);
          
          await admin.firestore().runTransaction(async (transaction) => {
            const productRefs = chunk.map((item) =>
              admin.firestore()
                .collection(item.productSource || 'shop_products')
                .doc(item.productId),
            );
            
            const productDocs = await Promise.all(
              productRefs.map((ref) => transaction.get(ref)),
            );

            for (let j = 0; j < productDocs.length; j++) {
              const doc = productDocs[j];
              const cartItem = chunk[j];
              
              if (!doc.exists) {
                throw new Error(`Product ${cartItem.productId} no longer exists`);
              }

              const product = doc.data();
              const {quantity, selectedColor} = cartItem;

              const availableStock = selectedColor && 
                product.colorQuantities && 
                product.colorQuantities[selectedColor] !== undefined ? 
                safeNumber(product.colorQuantities[selectedColor]) : 
                safeNumber(product.quantity);

              if (quantity > availableStock) {
                throw new Error(
                  `Insufficient stock for ${product.productName}. Available: ${availableStock}, Requested: ${quantity}`,
                );
              }

              if (selectedColor && product.colorQuantities && 
                  product.colorQuantities[selectedColor] !== undefined) {
                transaction.update(doc.ref, {
                  [`colorQuantities.${selectedColor}`]: 
                    admin.firestore.FieldValue.increment(-quantity),
                });
              } else {
                transaction.update(doc.ref, {
                  quantity: admin.firestore.FieldValue.increment(-quantity),
                });
              }
            }

            transaction.set(
              admin.firestore().collection('_stock_reservations').doc(),
              {
                userId,
                items: chunk.map((item) => ({
                  productId: item.productId,
                  quantity: item.quantity,
                  selectedColor: item.selectedColor || null,
                })),
                chunkIndex: Math.floor(i / TRANSACTION_CHUNK_SIZE),
                totalChunks: Math.ceil(cartItems.length / TRANSACTION_CHUNK_SIZE),
                reservedAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt: admin.firestore.Timestamp.fromMillis(
                  Date.now() + 10 * 60 * 1000,
                ),
                status: 'reserved',
              },
            );
          });
        }

        console.log('✅ Stock reserved successfully');
        validationResults.stockReserved = true;
      } catch (error) {
        console.error('❌ Stock reservation failed:', error);
        validationResults.isValid = false;
        validationResults.errors['_reservation'] = {
          key: 'reservation_failed',
          params: {},
        };
      }
    }

    // ============================================================
    // 6. LOGGING & RESPONSE
    // ============================================================
    const duration = Date.now() - startTime;
    
    console.log(`✅ Validation completed in ${duration}ms`, {
      userId,
      itemCount: cartItems.length,
      isValid: validationResults.isValid,
      errorCount: Object.keys(validationResults.errors).length,
      warningCount: Object.keys(validationResults.warnings).length,
    });

    return {
      ...validationResults,
      hasWarnings: Object.keys(validationResults.warnings).length > 0,
      validatedAt: admin.firestore.Timestamp.now(),
      processingTimeMs: duration,
    };
  },
);

// ============================================================================
// UPDATE CART CACHE
// ============================================================================

export const updateCartCache = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 60,
    memory: '512MiB',
    concurrency: 80,
    maxInstances: 100,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    const startTime = Date.now();
    
    // ============================================================
    // 1. AUTHENTICATION & RATE LIMITING
    // ============================================================
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = request.auth.uid;

    // Rate limit: 20 requests per 60 seconds per user
    const withinLimit = await checkRateLimit(`cart_update_rate:${userId}`, 20, 60);
    if (!withinLimit) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many update requests. Please wait a moment.',
      );
    }

    // ============================================================
    // 2. INPUT VALIDATION
    // ============================================================
    const {productUpdates} = request.data;

    if (!Array.isArray(productUpdates) || productUpdates.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'productUpdates must be a non-empty array',
      );
    }

    if (productUpdates.length > 500) {
      throw new HttpsError(
        'invalid-argument',
        'Cannot update more than 500 items at once',
      );
    }

    for (const update of productUpdates) {
      if (!update.productId || typeof update.productId !== 'string') {
        throw new HttpsError(
          'invalid-argument',
          'Each update must have a valid productId',
        );
      }
    }

    console.log(`🔄 Updating cart cache for ${productUpdates.length} items (user: ${userId})`);

    // ============================================================
    // 3. BATCH UPDATE CART DOCUMENTS
    // ============================================================
    const results = {
      updated: [],
      failed: [],
      skipped: [],
    };

    const BATCH_SIZE = 500;

    for (let i = 0; i < productUpdates.length; i += BATCH_SIZE) {
      const chunk = productUpdates.slice(i, i + BATCH_SIZE);
      const batch = admin.firestore().batch();

      for (const update of chunk) {
        const {productId, updates} = update;

        if (!updates || Object.keys(updates).length === 0) {
          results.skipped.push(productId);
          continue;
        }

        const cartDocRef = admin.firestore()
          .collection('users')
          .doc(userId)
          .collection('cart')
          .doc(productId);

        try {
          // ✅ Only update allowed fields
          const allowedFields = [
            'cachedPrice',
            'cachedBundleData',
            'cachedBundlePrice',
            'cachedDiscountPercentage',
            'cachedDiscountThreshold',
            'cachedBulkDiscountPercentage',
            'cachedMaxQuantity',
            'discountPercentage',
            'discountThreshold',
            'bulkDiscountPercentage',
            'maxQuantity',
            'unitPrice',
            'bundlePrice',
            'bundleData',
            'bundleIds',
            'updatedAt',
          ];

          const safeUpdates = {};
          for (const [key, value] of Object.entries(updates)) {
            if (allowedFields.includes(key)) {
              safeUpdates[key] = value;
            }
          }

          safeUpdates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

          if (Object.keys(safeUpdates).length > 1) {
            batch.update(cartDocRef, safeUpdates);
            results.updated.push(productId);
          } else {
            results.skipped.push(productId);
          }
        } catch (error) {
          console.error(`Failed to update ${productId}:`, error);
          results.failed.push({productId, error: error.message});
        }
      }

      try {
        await batch.commit();
        console.log(`✅ Batch ${Math.floor(i / BATCH_SIZE) + 1} committed`);
      } catch (error) {
        console.error(`❌ Batch commit failed:`, error);
        throw new HttpsError('internal', 'Failed to update cart cache');
      }
    }

    // ============================================================
    // 4. LOGGING & RESPONSE
    // ============================================================
    const duration = Date.now() - startTime;

    console.log(`✅ Cart cache update completed in ${duration}ms`, {
      userId,
      totalItems: productUpdates.length,
      updated: results.updated.length,
      skipped: results.skipped.length,
      failed: results.failed.length,
    });

    return {
      success: true,
      updated: results.updated.length,
      skipped: results.skipped.length,
      failed: results.failed.length,
      failedItems: results.failed,
      processingTimeMs: duration,
    };
  },
);

import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {FieldPath} from 'firebase-admin/firestore';
import admin from 'firebase-admin';

export const calculateCartTotals = onCall(
  {
    region: 'europe-west3',
    memory: '256MiB',
    timeoutSeconds: 30,
    maxInstances: 100,      
    concurrency: 80,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be logged in');
    }

    const userId = request.auth.uid;
    const {selectedProductIds} = request.data;

    if (!Array.isArray(selectedProductIds) || selectedProductIds.length === 0) {
      return {
        total: 0,
        currency: 'TL',
        items: [],
        calculatedAt: new Date().toISOString(),
      };
    }

    // Rate limiting
    const rateLimitRef = admin.firestore().collection('_rate_limits').doc(`cart_totals:${userId}`);
const rateLimitDoc = await rateLimitRef.get();

const now = Date.now();
const windowMs = 10000; // 10 seconds
const maxCalls = 5; // 5 calls per window

if (rateLimitDoc.exists) {
  const data = rateLimitDoc.data();
  const calls = data.calls || [];
  
  // Remove calls outside the current window
  const recentCalls = calls.filter((timestamp) => now - timestamp < windowMs);
  
  if (recentCalls.length >= maxCalls) {
    throw new HttpsError('resource-exhausted', 'Too many requests. Please wait.');
  }
  
  // Add current call
  recentCalls.push(now);
  await rateLimitRef.set({calls: recentCalls}, {merge: true}); // ✅ This is correct - you're already doing this
} else {
  await rateLimitRef.set({calls: [now]});
}

    try {
      // Fetch cart items
      const cartItems = [];
      const cartRef = admin.firestore().collection('users').doc(userId).collection('cart');

      if (selectedProductIds.length <= 10) {
        const snapshot = await cartRef
          .where(FieldPath.documentId(), 'in', selectedProductIds)
          .get();

        snapshot.forEach((doc) => {
          cartItems.push({productId: doc.id, ...doc.data()});
        });
      } else {
        const batches = [];
        for (let i = 0; i < selectedProductIds.length; i += 10) {
          const batch = selectedProductIds.slice(i, i + 10);
          batches.push(cartRef.where(FieldPath.documentId(), 'in', batch).get());
        }

        const snapshots = await Promise.all(batches);
        snapshots.forEach((snapshot) => {
          snapshot.forEach((doc) => {
            cartItems.push({productId: doc.id, ...doc.data()});
          });
        });
      }

      if (cartItems.length === 0) {
        return {
          total: 0,
          currency: 'TL',
          items: [],
          calculatedAt: new Date().toISOString(),
        };
      }

      // ✅ NEW: Fetch bundles using bundleData from products
      const applicableBundles = [];
      const uniqueBundleIds = new Set();
      
      // Collect all bundle IDs from cart items
      cartItems.forEach((item) => {
        if (item.bundleData && Array.isArray(item.bundleData)) {
          item.bundleData.forEach((bd) => {
            if (bd.bundleId) {
              uniqueBundleIds.add(bd.bundleId);
            }
          });
        }
      });

      // Fetch bundle documents
      if (uniqueBundleIds.size > 0) {
        const bundlePromises = Array.from(uniqueBundleIds).map((bundleId) =>
          admin.firestore().collection('bundles').doc(bundleId).get(),
        );
        const bundleDocs = await Promise.all(bundlePromises);
        
        bundleDocs.forEach((doc) => {
          if (doc.exists) {
            const bundleData = doc.data();
            
            // ✅ Check if cart contains ALL products from this bundle
            const bundleProductIds = bundleData.products.map((p) => p.productId);
            const cartProductIds = cartItems.map((item) => item.productId);
            
            const hasAllProducts = bundleProductIds.every((id) => 
              cartProductIds.includes(id),
            );
            
            if (hasAllProducts) {
              applicableBundles.push({
                bundleId: doc.id,
                ...bundleData,
                productIds: bundleProductIds,
                savings: bundleData.totalOriginalPrice - bundleData.totalBundlePrice,
              });
            }
          }
        });
      }

      // ✅ Step 2: Select best bundle (highest savings)
      let selectedBundle = null;
      if (applicableBundles.length > 0) {
        applicableBundles.sort((a, b) => b.savings - a.savings);
        selectedBundle = applicableBundles[0];
        
        console.log(`✅ Applying bundle ${selectedBundle.bundleId}: Save ${selectedBundle.savings}`);
      }

      // ✅ Step 3: Calculate totals
      const itemTotals = [];
      let total = 0.0;
      let currency = 'TL';
      const bundledProductIds = new Set(selectedBundle ? selectedBundle.productIds : []);

      // Apply bundle price if selected
      if (selectedBundle) {
        // Find minimum quantity across all bundle products
        const bundleItems = cartItems.filter((item) => 
          bundledProductIds.has(item.productId),
        );
        
        const minQuantity = Math.min(...bundleItems.map((item) => item.quantity || 1));
        
        // Add bundle price
        const bundleTotal = selectedBundle.totalBundlePrice * minQuantity;
        total += bundleTotal;
        currency = selectedBundle.currency || 'TL';
        
        itemTotals.push({
          bundleId: selectedBundle.bundleId,
          bundleName: `Bundle (${selectedBundle.productIds.length} products)`,
          unitPrice: selectedBundle.totalBundlePrice,
          total: bundleTotal,
          quantity: minQuantity,
          isBundle: true,
          productIds: selectedBundle.productIds,
        });
        
        // Handle extra quantities beyond bundle set
        for (const item of bundleItems) {
          const remainingQty = (item.quantity || 1) - minQuantity;
          
          if (remainingQty > 0) {
            let unitPrice = item.unitPrice || item.cachedPrice || 0;
            
            // Apply bulk discount to extra units
            const discountThreshold = item.discountThreshold || item.cachedDiscountThreshold;
            const bulkDiscountPercentage = item.bulkDiscountPercentage || item.cachedBulkDiscountPercentage;
            
            if (discountThreshold && bulkDiscountPercentage && remainingQty >= discountThreshold) {
              unitPrice = unitPrice * (1 - bulkDiscountPercentage / 100);
            }
            
            const itemTotal = unitPrice * remainingQty;
            total += itemTotal;
            
            itemTotals.push({
              productId: item.productId,
              unitPrice,
              total: itemTotal,
              quantity: remainingQty,
              isBundle: false,
            });
          }
        }
      }

      // Process non-bundled products
      for (const item of cartItems) {
        if (bundledProductIds.has(item.productId)) continue;
        
        const quantity = item.quantity || 1;
        let unitPrice = item.unitPrice || item.cachedPrice || 0;
        
        // Apply bulk discount
        const discountThreshold = item.discountThreshold || item.cachedDiscountThreshold;
        const bulkDiscountPercentage = item.bulkDiscountPercentage || item.cachedBulkDiscountPercentage;
        
        if (discountThreshold && bulkDiscountPercentage && quantity >= discountThreshold) {
          unitPrice = unitPrice * (1 - bulkDiscountPercentage / 100);
        }
        
        const itemTotal = unitPrice * quantity;
        total += itemTotal;
        currency = item.currency || 'TL';
        
        itemTotals.push({
          productId: item.productId,
          unitPrice,
          total: itemTotal,
          quantity,
          isBundle: false,
        });
      }

      // Validation
      if (total < 0) {
        console.error('❌ Negative total detected!', {total, items: itemTotals});
        throw new HttpsError('internal', 'Invalid total calculated');
      }

      return {
        total: Math.round(total * 100) / 100,
        currency,
        items: itemTotals,
        appliedBundle: selectedBundle ? {
          bundleId: selectedBundle.bundleId,
          savings: selectedBundle.savings,
          productCount: selectedBundle.productIds.length,
        } : null,
        calculatedAt: new Date().toISOString(),
      };
    } catch (error) {
      console.error('❌ Calculate totals error:', error);
      throw new HttpsError('internal', 'Failed to calculate totals');
    }
  },
);

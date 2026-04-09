import {onCall, HttpsError} from 'firebase-functions/v2/https';
import vision from '@google-cloud/vision';
const visionClient = new vision.ImageAnnotatorClient();

export const moderateImage = onCall(
    {region: 'europe-west3'},
    async (req) => {
      const auth = req.auth;
      if (!auth) {
        throw new HttpsError('unauthenticated', 'You must be signed in.');
      }
  
      const {imageUrl} = req.data || {};
      
      if (!imageUrl || typeof imageUrl !== 'string') {
        throw new HttpsError('invalid-argument', 'Invalid image URL provided.');
      }
  
      try {
        const [result] = await visionClient.safeSearchDetection(imageUrl);
        const safeSearch = result.safeSearchAnnotation;
  
        if (!safeSearch) {
          return {approved: true};
        }
  
        // ✅ E-commerce appropriate: Only block EXPLICIT content
        // Bikinis, lingerie, fashion = OK
        // Explicit nudity/pornography = NOT OK
        const isInappropriate = 
          safeSearch.adult === 'VERY_LIKELY' || // Only explicit pornography
          safeSearch.violence === 'VERY_LIKELY'; // Only extreme violence
          // Note: We're NOT blocking "racy" at all - swimwear/fashion is fine!
  
        let rejectionReason = null;
        if (safeSearch.adult === 'VERY_LIKELY') {
          rejectionReason = 'adult_content';
        } else if (safeSearch.violence === 'VERY_LIKELY') {
          rejectionReason = 'violent_content';
        }
  
        // 🔍 Add logging to see what Vision API returns (helpful for debugging)
        console.log('Vision API results:', {
          adult: safeSearch.adult,
          violence: safeSearch.violence,
          racy: safeSearch.racy,
          approved: !isInappropriate,
        });
  
        return {
          approved: !isInappropriate,
          rejectionReason,
          details: {
            adult: safeSearch.adult,
            violence: safeSearch.violence,
            racy: safeSearch.racy,
          },
        };
      } catch (error) {
        console.error('Vision API error:', error);
        return {approved: true, error: 'processing_error'};
      }
    },
  );

// lib/screens/food/receipt_scanner.dart

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCAN RESULT MODEL
// ─────────────────────────────────────────────────────────────────────────────

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

class ReceiptScanResult {
  final String rawText;
  final String? detectedAddress;
  final double? detectedTotal;
  final String? detectedOrderId;
  final String? detectedPhone;
  final LatLng? detectedLatLng;
  final List<String> detectedQrUrls;
  final List<Map<String, dynamic>> detectedItems;
  final double confidence;

  const ReceiptScanResult({
    required this.rawText,
    this.detectedAddress,
    this.detectedTotal,
    this.detectedOrderId,
    this.detectedPhone,
    this.detectedLatLng,
    this.detectedQrUrls = const [],
    this.detectedItems = const [],
    required this.confidence,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCANNER SERVICE
// ML Kit does OCR (free, on-device)
// CF parseReceiptText calls Claude Haiku server-side (~$0.00004 per scan).
// Keeps the Anthropic key out of the app binary and surfaces extraction
// failures in Cloud Logging.
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptScannerService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _picker = ImagePicker();

  final _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  Future<ReceiptScanResult?> scanFromCamera(BuildContext context) async {
    // No imageQuality compression — QR codes occupy a small fraction of the
    // frame and JPEG artifacts at 90% quality can break ML Kit's decoder.
    // The receipt photo is already uploaded only to OCR + the scan CF, so
    // the larger payload is only paid once per scan.
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (photo == null) return null;
    return _processImage(photo.path);
  }

  Future<ReceiptScanResult?> scanFromGallery() async {
    final photo = await _picker.pickImage(source: ImageSource.gallery);
    if (photo == null) return null;
    return _processImage(photo.path);
  }

  Future<ReceiptScanResult> _processImage(String path) async {
    final inputImage = InputImage.fromFilePath(path);

    // Run OCR and QR scan in parallel — same image, no extra cost
    final results = await Future.wait([
      _recognizer.processImage(inputImage),
      _barcodeScanner.processImage(inputImage),
    ]);

    final recognized = results[0] as RecognizedText;
    final barcodes = results[1] as List<Barcode>;
    final rawText = recognized.text;

    // Capture every QR raw value so the CF can fall back to server-side
    // resolution when the client can't follow the redirect (KKTC streets
    // missing from Google Geocoding make the QR the only reliable source).
    final qrUrls = barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.trim().isNotEmpty)
        .toList(growable: false);
    debugPrint('[QR] ML Kit detected ${qrUrls.length} barcode(s): $qrUrls');

    // Try to extract coordinates from any QR code found
    final coords = await _extractCoordsFromBarcodes(barcodes);

    // Haiku extracts the rest
    final extracted = await _extractWithHaiku(rawText);

    final rawItems = extracted['items'] as List? ?? [];
    final items = rawItems.whereType<Map<String, dynamic>>().toList();

    return ReceiptScanResult(
      rawText: rawText,
      detectedAddress: extracted['address'] as String?,
      detectedTotal: (extracted['total'] as num?)?.toDouble(),
      detectedOrderId: extracted['order_id'] as String?,
      detectedPhone: extracted['phone'] as String?,
      detectedLatLng: coords,
      detectedQrUrls: qrUrls,
      detectedItems: items,
      confidence: rawText.length > 100 ? 0.85 : 0.3,
    );
  }

  Future<LatLng?> _extractCoordsFromBarcodes(List<Barcode> barcodes) async {
    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      // Try direct coordinate patterns first
      final direct = _tryExtractFromUrl(raw);
      if (direct != null) return direct;

      // If it's a shortened URL, follow the redirect to get real coordinates
      if (raw.contains('goo.gl') ||
          raw.contains('maps.app') ||
          raw.contains('bit.ly')) {
        final resolved = await _followRedirect(raw);
        if (resolved != null) {
          final fromResolved = _tryExtractFromUrl(resolved);
          if (fromResolved != null) return fromResolved;
        }
      }
    }
    return null;
  }

  LatLng? _tryExtractFromUrl(String raw) {
    // geo:35.1933,33.8274
    final geoMatch = RegExp(r'geo:(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(raw);
    if (geoMatch != null) {
      final lat = double.tryParse(geoMatch.group(1)!);
      final lng = double.tryParse(geoMatch.group(2)!);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    // ?q=35.1933,33.8274
    final qMatch =
        RegExp(r'[?&]q=(?:loc:)?(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(raw);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1)!);
      final lng = double.tryParse(qMatch.group(2)!);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    // @35.1933,33.8274,15z
    final atMatch = RegExp(r'@(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(raw);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    return null;
  }

  Future<String?> _followRedirect(String shortUrl) async {
    final client = http.Client();
    try {
      String currentUrl = shortUrl;

      for (int i = 0; i < 5; i++) {
        debugPrint('[QR] Hop $i: $currentUrl');

        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36'
          ..headers['Accept-Language'] = 'tr-TR,tr;q=0.9,en;q=0.8';

        final response =
            await client.send(request).timeout(const Duration(seconds: 8));

        debugPrint('[QR] Status: ${response.statusCode}');
        debugPrint('[QR] Location header: ${response.headers['location']}');

        final location = response.headers['location'];

        if (location == null) {
          // No Location header — extract from response body. Google Maps
          // landing pages embed coords in og:url / canonical / inline JS.
          final body = await response.stream.bytesToString();
          final fromBody = _tryExtractFromBody(body);
          if (fromBody != null) {
            debugPrint('[QR] Extracted from body: $fromBody');
            return fromBody;
          }
          debugPrint(
              '[QR] Body snippet: ${body.substring(0, body.length.clamp(0, 300))}');
          return currentUrl;
        }

        if (_tryExtractFromUrl(location) != null) return location;
        currentUrl = location;
      }

      return currentUrl;
    } catch (e) {
      debugPrint('[QR] Redirect error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // Look inside a redirect-target HTML body for coordinate hints.
  // Google Maps landing pages embed coords in several stable places.
  String? _tryExtractFromBody(String body) {
    // Trim to first 50 KB so a malicious or huge page can't blow memory.
    final scope = body.length > 50000 ? body.substring(0, 50000) : body;

    // og:url meta with `?q=lat,lng` or `@lat,lng`
    final og = RegExp(
      r'''<meta[^>]*property=["']og:url["'][^>]*content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(scope);
    if (og != null) {
      final candidate = og.group(1)!;
      if (_tryExtractFromUrl(candidate) != null) return candidate;
    }

    // <link rel="canonical" href="...">
    final canonical = RegExp(
      r'''<link[^>]*rel=["']canonical["'][^>]*href=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(scope);
    if (canonical != null) {
      final candidate = canonical.group(1)!;
      if (_tryExtractFromUrl(candidate) != null) return candidate;
    }

    // Inline @lat,lng pattern anywhere in the body — last resort.
    final inline =
        RegExp(r'@(-?\d{1,2}\.\d{4,}),(-?\d{1,3}\.\d{4,})').firstMatch(scope);
    if (inline != null) {
      return '@${inline.group(1)},${inline.group(2)}';
    }

    return null;
  }

  // ── Haiku extraction (via Cloud Function) ─────────────────────────────────

  Future<Map<String, dynamic>> _extractWithHaiku(String rawText) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable(
        'parseReceiptText',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final response = await callable.call({'rawText': rawText});
      final data = Map<String, dynamic>.from(response.data as Map);
      debugPrint('[ReceiptScanner] CF extracted: $data');
      return data;
    } catch (e) {
      debugPrint('[ReceiptScanner] CF failed: $e — using regex fallback');
      return _fallbackRegex(rawText);
    }
  }

  // ── Regex fallback (used if API key missing or Haiku call fails) ───────────

  Map<String, dynamic> _fallbackRegex(String text) {
    return {
      'address': _regexAddress(text),
      'total': _regexTotal(text),
      'order_id': _regexOrderId(text),
      'phone': _regexPhone(text),
      'items': [],
    };
  }

  String? _regexAddress(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('sokak') ||
          lower.contains('cadde') ||
          lower.contains('mahalle') ||
          lower.contains('apt') ||
          lower.contains('no:') ||
          lower.contains('adres') ||
          lower.contains('kyk') ||
          lower.contains('yurdu') ||
          lower.contains('üniversite') ||
          lower.contains('universitesi') ||
          lower.contains('kktc') ||
          lower.contains('kibris') ||
          lower.contains('kıbrıs') ||
          lower.contains('lefkoşa') ||
          lower.contains('gazimağusa') ||
          lower.contains('girne') ||
          lower.contains('iskele')) {
        return line.trim();
      }
    }
    return null;
  }

  double? _regexTotal(String text) {
    final patterns = [
      RegExp(r'(?:toplam|total|genel toplam)[:\s]*([0-9]+[.,][0-9]{0,2})',
          caseSensitive: false),
      RegExp(r'([0-9]+[.,][0-9]{0,2})\s*TL', caseSensitive: false),
      RegExp(r'TL\s*([0-9]+[.,][0-9]{0,2})', caseSensitive: false),
      RegExp(r'([0-9]{2,}[.,][0-9]{1,2})[^0-9]'),
    ];

    final candidates = <double>[];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final raw = match
            .group(1)!
            .replaceAll(',', '.')
            .replaceAll(RegExp(r'[^0-9.]'), '');
        final value = double.tryParse(raw);
        if (value != null && value > 0) candidates.add(value);
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort();
    return candidates.last; // Grand total is usually the largest number
  }

  String? _regexOrderId(String text) {
    final match = RegExp(r'\b([A-F0-9]{8})\b').firstMatch(text);
    return match?.group(1);
  }

  String? _regexPhone(String text) {
    final match = RegExp(r'(?:tel|telefon|gsm)[;:\s]*(\+?[0-9\s\-]{10,15})',
            caseSensitive: false)
        .firstMatch(text);
    return match?.group(1)?.trim();
  }

  void dispose() {
    _recognizer.close();
    _barcodeScanner.close(); // ← add this
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCAN SCREEN
//
// Two modes:
//   1. Default (const ReceiptScanScreen())
//      Legacy mode — scans to find an existing order
//      assigned to this courier in My Deliveries.
//      Returns the full orderId via Navigator.pop.
//
//   2. Call mode (ReceiptScanScreen.forCall(courierCall: ...))
//      Scans receipt for an external (non-app) order,
//      calls createScannedFoodOrder Cloud Function,
//      creates a new orders-food document, and returns
//      the new orderId via Navigator.pop.
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptScanScreen extends StatefulWidget {
  final String? restaurantId;
  final String? restaurantName;

  /// Legacy mode — find an existing delivery by order ID
  const ReceiptScanScreen({super.key})
      : restaurantId = null,
        restaurantName = null;

  /// Restaurant mode — restaurant scans receipt, creates order as accepted
  const ReceiptScanScreen.forRestaurant({
    super.key,
    required String restaurantId,
    String? restaurantName,
  })  : restaurantId = restaurantId,
        restaurantName = restaurantName;

  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  final _service = ReceiptScannerService();
  bool _scanning = false;
  String? _error;
  String? _statusMessage;

  bool get _isRestaurantMode => widget.restaurantId != null;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _scanning = true;
      _error = null;
      _statusMessage =
          _isRestaurantMode ? 'Fiş okunuyor...' : 'Fiş taranıyor...';
    });

    try {
      final result = source == ImageSource.camera
          ? await _service.scanFromCamera(context)
          : await _service.scanFromGallery();

      if (result == null || !mounted) return;

      if (_isRestaurantMode) {
        setState(() => _statusMessage = 'Sipariş oluşturuluyor...');
        await _handleRestaurantModeScan(result);
      } else {
        await _handleLegacyModeScan(result);
      }
    } catch (e) {
      setState(() => _error =
          'Tarama başarısız: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ── Call mode: create a new order via Cloud Function ──────────────────────

  Future<void> _handleRestaurantModeScan(ReceiptScanResult result) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('createScannedRestaurantOrder');

    final response = await callable.call({
      'restaurantId': widget.restaurantId,
      'scannedRawText': result.rawText,
      'detectedAddress': result.detectedAddress,
      'detectedTotal': result.detectedTotal,
      'detectedPhone': result.detectedPhone,
      'detectedLat': result.detectedLatLng?.lat,
      'detectedLng': result.detectedLatLng?.lng,
      'detectedQrUrls': result.detectedQrUrls,
      'detectedItems': result.detectedItems,
    });

    final orderId = response.data['orderId'] as String?;

    if (orderId != null && mounted) {
      Navigator.of(context).pop(orderId);
    } else {
      setState(() => _error =
          'Sipariş oluşturuldu fakat ID alınamadı. Siparişler sekmesini kontrol edin.');
    }
  }

  // ── Legacy mode: find an existing delivery by order ID ────────────────────

  Future<void> _handleLegacyModeScan(ReceiptScanResult result) async {
    if (result.detectedOrderId == null) {
      setState(() => _error =
          'Fişte sipariş numarası bulunamadı.\nSipariş numarasının görünür olduğundan emin olun ve tekrar deneyin.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;

    final query = await FirebaseFirestore.instance
        .collection('orders-food')
        .where('cargoUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'out_for_delivery')
        .get();

    final match = query.docs
        .where((d) => d.id.toUpperCase().startsWith(result.detectedOrderId!))
        .toList();

    if (match.isEmpty) {
      setState(() => _error =
          '#${result.detectedOrderId} numaralı sipariş aktif teslimatlarınızda bulunamadı.');
      return;
    }

    if (mounted) Navigator.of(context).pop(match.first.id);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        elevation: 0,
        title: Text(
          _isRestaurantMode ? 'Fişi Tara' : 'Scan Receipt',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon circle
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(isDark ? 0.13 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.document_scanner_rounded,
                          size: 48, color: Colors.orange),
                    ),
                    const SizedBox(height: 24),

                    // Restaurant name chip (call mode only)
                    if (_isRestaurantMode && widget.restaurantName != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storefront_rounded,
                                size: 14, color: Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                              widget.restaurantName!,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Title
                    Text(
                      _isRestaurantMode
                          ? 'Müşteri fişini tara'
                          : 'Siparişi bul',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      _isRestaurantMode
                          ? 'Harici fişi okuyarak sipariş kaydı oluşturulacak.'
                          : 'Uygulama sipariş numarasını okuyarak sizi ilgili teslimat kartına yönlendirecek.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Buttons or spinner
                    if (_scanning)
                      Column(
                        children: [
                          const CircularProgressIndicator(color: Colors.orange),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage ?? 'İşleniyor...',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _scan(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('Fotoğraf Çek',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _scan(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('Galeriden Seç',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],

                    // Error box
                    if (_error != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.withOpacity(0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}

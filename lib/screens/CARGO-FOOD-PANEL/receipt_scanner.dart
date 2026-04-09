// lib/screens/food/receipt_scanner.dart

import 'dart:convert';
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
  final List<Map<String, dynamic>> detectedItems;
  final double confidence;

  const ReceiptScanResult({
    required this.rawText,
    this.detectedAddress,
    this.detectedTotal,
    this.detectedOrderId,
    this.detectedPhone,
    this.detectedLatLng,
    this.detectedItems = const [],
    required this.confidence,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCANNER SERVICE
// ML Kit does OCR (free, on-device)
// Claude Haiku does extraction (intelligent, ~$0.00004 per scan)
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptScannerService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _picker = ImagePicker();

  // API key passed via --dart-define=ANTHROPIC_API_KEY=...
  static const _apiKey =
      String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

  final _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  Future<ReceiptScanResult?> scanFromCamera(BuildContext context) async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
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
          ..followRedirects = false;

        final response =
            await client.send(request).timeout(const Duration(seconds: 5));

        debugPrint('[QR] Status: ${response.statusCode}');
        debugPrint('[QR] Location header: ${response.headers['location']}');

        final location = response.headers['location'];

        if (location == null) {
          // No Location header — try reading body for JS redirect
          final body = await response.stream.bytesToString();
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

  // ── Haiku extraction ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _extractWithHaiku(String rawText) async {
    if (_apiKey.isEmpty) {
      debugPrint('[ReceiptScanner] No API key — falling back to regex');
      return _fallbackRegex(rawText);
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': _apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': 'claude-haiku-4-5-20251001',
              'max_tokens': 1024,
              'messages': [
                {
                  'role': 'user',
                  'content':
                      '''Extract delivery information from this receipt OCR text.
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
  4. Fix garbled digits like 250,7: → 250.75, 295,0( → 295.00.
  Return as a plain number with no currency symbol.
- address: look for street names, district, city, postal code. In North Cyprus receipts look for KKTC, Kuzey Kıbrıs, Lefkoşa, Gazimağusa, Girne, İskele, KYK, yurdu, üniversite, DAÜ, GAÜ, NEU. Return the full address on one line.
- phone: look for TEL, telefon, GSM patterns. Include + prefix if present.
- order_id: look for sipariş no, order no, receipt no, # prefixed codes.
- items: extract each food/drink item with its name, quantity, and unit price. Skip non-food lines like delivery fee, discount, tax, subtotal, total. If quantity is not shown, assume 1. Fix OCR errors in names. Return empty array if no items found.

Receipt OCR text:
${rawText.length > 1500 ? rawText.substring(0, 1500) : rawText}'''
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
            '[ReceiptScanner] Haiku error ${response.statusCode}: ${response.body}');
        return _fallbackRegex(rawText);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (data['content'] as List).first['text'] as String;

      // Strip markdown fences if model adds them despite instructions
      final clean =
          content.replaceAll('```json', '').replaceAll('```', '').trim();

      final parsed = jsonDecode(clean) as Map<String, dynamic>;
      debugPrint('[ReceiptScanner] Haiku extracted: $parsed');
      return parsed;
    } catch (e) {
      debugPrint('[ReceiptScanner] Haiku failed: $e — using regex fallback');
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight -
                48,
          ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
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
                _isRestaurantMode ? 'Müşteri fişini tara' : 'Siparişi bul',
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
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
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
            ],
          ),
        ),
      ),
    );
  }
}

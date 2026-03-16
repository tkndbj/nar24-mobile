// lib/screens/food/receipt_scanner.dart

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'food_cargo_screen.dart'; // for CourierCall

// ─────────────────────────────────────────────────────────────────────────────
// SCAN RESULT MODEL
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptScanResult {
  final String rawText;
  final String? detectedAddress;
  final double? detectedTotal;
  final String? detectedOrderId;
  final double confidence;

  const ReceiptScanResult({
    required this.rawText,
    this.detectedAddress,
    this.detectedTotal,
    this.detectedOrderId,
    required this.confidence,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCANNER SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptScannerService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _picker = ImagePicker();

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
    final recognized = await _recognizer.processImage(inputImage);
    final rawText = recognized.text;

    return ReceiptScanResult(
      rawText: rawText,
      detectedAddress: _extractAddress(rawText),
      detectedTotal: _extractTotal(rawText),
      detectedOrderId: _extractOrderId(rawText),
      confidence: _estimateConfidence(rawText),
    );
  }

  String? _extractAddress(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('sokak') ||
          lower.contains('cadde') ||
          lower.contains('mahalle') ||
          lower.contains('apt') ||
          lower.contains('no:') ||
          lower.contains('adres')) {
        return line.trim();
      }
    }
    return null;
  }

  double? _extractTotal(String text) {
    final patterns = [
      RegExp(r'(?:toplam|total|genel toplam)[:\s]*([0-9]+[.,][0-9]{0,2})',
          caseSensitive: false),
      RegExp(r'([0-9]+[.,][0-9]{0,2})\s*TL', caseSensitive: false),
      RegExp(r'TL\s*([0-9]+[.,][0-9]{0,2})', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final raw = match.group(1)!.replaceAll(',', '.');
        return double.tryParse(raw);
      }
    }
    return null;
  }

  String? _extractOrderId(String text) {
    final match = RegExp(r'\b([A-F0-9]{8})\b').firstMatch(text);
    return match?.group(1);
  }

  double _estimateConfidence(String text) {
    if (text.length < 20) return 0.1;
    if (text.length < 100) return 0.5;
    return 0.85;
  }

  void dispose() => _recognizer.close();
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
  final CourierCall? courierCall;

  /// Legacy mode — find an existing delivery by order ID
  const ReceiptScanScreen({super.key}) : courierCall = null;

  /// Call mode — create a new scanned order
  const ReceiptScanScreen.forCall({
    super.key,
    required CourierCall courierCall,
  }) : courierCall = courierCall;

  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  final _service = ReceiptScannerService();
  bool _scanning = false;
  String? _error;

  bool get _isCallMode => widget.courierCall != null;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final result = source == ImageSource.camera
          ? await _service.scanFromCamera(context)
          : await _service.scanFromGallery();

      if (result == null || !mounted) return;

      if (_isCallMode) {
        await _handleCallModeScan(result);
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

  Future<void> _handleCallModeScan(ReceiptScanResult result) async {
    final call = widget.courierCall!;

    final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('createScannedFoodOrder');

    final response = await callable.call({
      'callId': call.id,
      'scannedRawText': result.rawText,
      'detectedAddress': result.detectedAddress,
      'detectedTotal': result.detectedTotal,
    });

    final orderId = response.data['orderId'] as String?;

    if (orderId != null && mounted) {
      Navigator.of(context).pop(orderId);
    } else {
      setState(() => _error =
          'Sipariş oluşturuldu fakat ID alınamadı. Teslimatlarım sekmesini kontrol edin.');
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
          _isCallMode ? 'Fişi Tara' : 'Scan Receipt',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
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
            if (_isCallMode) ...[
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
                      widget.courierCall!.restaurantName,
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
              _isCallMode ? 'Müşteri fişini tara' : 'Siparişi bul',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              _isCallMode
                  ? '${widget.courierCall!.restaurantName} için harici fişi okuyarak teslimat kaydı oluşturulacak.'
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
                    _isCallMode
                        ? 'Fiş okunuyor ve sipariş oluşturuluyor...'
                        : 'Fiş okunuyor...',
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
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

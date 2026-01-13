import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import '../../generated/l10n/app_localizations.dart';

/// Result returned from QR scan verification
class QRScanResult {
  final bool success;
  final String? errorMessage;
  final Map<String, dynamic>? orderData;
  final bool skipped;
  final bool markedAsDelivered;

  QRScanResult({
    required this.success,
    this.errorMessage,
    this.orderData,
    this.skipped = false,
    this.markedAsDelivered = false,
  });
}

/// QR Scanner screen for cargo delivery verification
class CargoQRScan extends StatefulWidget {
  final String orderId;
  final String buyerId;
  final String buyerName;

  const CargoQRScan({
    Key? key,
    required this.orderId,
    required this.buyerId,
    required this.buyerName,
  }) : super(key: key);

  @override
  State<CargoQRScan> createState() => _CargoQRScanState();
}

class _CargoQRScanState extends State<CargoQRScan> {
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  bool _hasScanned = false;
  String? _errorMessage;
  bool _torchEnabled = false;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _toggleTorch() {
    _scannerController?.toggleTorch();
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
  }

  /// Get current location for delivery verification
  Future<Map<String, double>?> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 5));
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
    } catch (e) {
      return null;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || _hasScanned || _showSuccess) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    setState(() {
      _isProcessing = true;
      _hasScanned = true;
      _errorMessage = null;
    });

    final l10n = AppLocalizations.of(context);

    try {
      final qrData = barcode.rawValue!;

      // Parse QR data
      Map<String, dynamic> parsedData;
      try {
        parsedData = json.decode(qrData);
      } catch (e) {
        throw Exception(l10n.invalidQRCode);
      }

      // Verify QR type is DELIVERY
      if (parsedData['type'] != 'DELIVERY') {
        throw Exception(l10n.invalidQRCode);
      }

      // Verify order ID matches
      if (parsedData['orderId'] != widget.orderId) {
        throw Exception(l10n.qrCodeMismatch);
      }

      // Verify buyer ID matches
      if (parsedData['buyerId'] != widget.buyerId) {
        throw Exception(l10n.qrCodeMismatch);
      }

      // Get current location for verification logging
      final location = await _getCurrentLocation();

      // Call markQRScanned to verify AND mark as delivered on server
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('markQRScanned');

      final result = await callable.call({
        'qrData': qrData,
        'scannedLocation': location,
        'notes': 'Scanned via cargo app',
      });

      final data = result.data as Map<String, dynamic>;

      if (data['success'] == true) {
        // Stop the scanner
        _scannerController?.stop();

        // Show success state
        setState(() {
          _isProcessing = false;
          _showSuccess = true;
        });

        // Wait to show success message, then navigate back
        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          Navigator.pop(
            context,
            QRScanResult(
              success: true,
              orderData: data,
              markedAsDelivered: true,
            ),
          );
        }
      } else {
        throw Exception(data['error'] ?? l10n.qrVerificationFailed);
      }
    } catch (e) {
      String errorMsg;
      if (e is FirebaseFunctionsException) {
        errorMsg = e.message ?? l10n.qrVerificationFailed;
      } else {
        errorMsg = e.toString().replaceFirst('Exception: ', '');
      }

      // Show error and stay on screen - let user retry or go back manually
      setState(() {
        _errorMessage = errorMsg;
        _isProcessing = false;
        _hasScanned = false; // Allow retry
      });

      // Keep error visible for 4 seconds, then allow retry
      await Future.delayed(const Duration(seconds: 4));
      if (mounted && _errorMessage == errorMsg) {
        setState(() {
          _errorMessage = null;
        });
      }
    }
  }

  void _skipQRVerification() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            const Icon(FeatherIcons.alertTriangle, color: Colors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.skipQRVerification,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.skipQRVerificationMessage,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              Navigator.pop(
                context,
                QRScanResult(
                  success: true,
                  skipped: true,
                  markedAsDelivered: false, // Not marked, needs manual marking
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(l10n.skipAndContinue),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FeatherIcons.x, color: Colors.white),
          onPressed: () => Navigator.pop(
            context,
            QRScanResult(success: false, errorMessage: 'Cancelled'),
          ),
        ),
        title: Text(
          l10n.scanQRCode,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _torchEnabled ? FeatherIcons.zap : FeatherIcons.zapOff,
              color: _torchEnabled ? Colors.yellow : Colors.white,
            ),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera scanner
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),

          // Overlay with scan area
          CustomPaint(
            size: size,
            painter: _ScanOverlayPainter(
              scanAreaSize: size.width * 0.7,
              borderColor: _errorMessage != null ? Colors.red : Colors.green,
            ),
          ),

          // Info card at top
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        FeatherIcons.user,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.buyerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.scanBuyerQRToVerify,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Processing indicator
          if (_isProcessing)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.verifyingQRCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Error message
          if (_errorMessage != null && !_showSuccess)
            Positioned(
              bottom: 150,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          FeatherIcons.alertCircle,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.positionQRInFrame,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Success overlay - shown when QR verified and delivery confirmed
          if (_showSuccess)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.qrVerifiedDeliveryConfirmed,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.buyerName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom actions - hidden when success overlay is shown
          if (!_showSuccess)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  if (_errorMessage == null)
                    Text(
                      l10n.positionQRInFrame,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _skipQRVerification,
                      icon: const Icon(FeatherIcons.skipForward, size: 18),
                      label: Text(l10n.skipQRVerification),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter for scan overlay
class _ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final Color borderColor;

  _ScanOverlayPainter({
    required this.scanAreaSize,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scanRect = Rect.fromCenter(
      center: center,
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Draw dark overlay outside scan area
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(scanRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Draw corners
    final cornerPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(
      scanRect.topLeft,
      scanRect.topLeft + const Offset(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanRect.topLeft,
      scanRect.topLeft + const Offset(0, cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      scanRect.topRight,
      scanRect.topRight + const Offset(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanRect.topRight,
      scanRect.topRight + const Offset(0, cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      scanRect.bottomLeft,
      scanRect.bottomLeft + const Offset(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanRect.bottomLeft,
      scanRect.bottomLeft + const Offset(0, -cornerLength),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      scanRect.bottomRight,
      scanRect.bottomRight + const Offset(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanRect.bottomRight,
      scanRect.bottomRight + const Offset(0, -cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor;
  }
}

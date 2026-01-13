import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../generated/l10n/app_localizations.dart';
import 'isbank_ads_images_payment_screen.dart';

class DynamicPaymentScreen extends StatefulWidget {
  final String submissionId;
  final String adType;
  final String duration;
  final double price;
  final String imageUrl;
  final String shopName;
  final String paymentLink;

  const DynamicPaymentScreen({
    super.key,
    required this.submissionId,
    required this.adType,
    required this.duration,
    required this.price,
    required this.imageUrl,
    required this.shopName,
    required this.paymentLink,
  });

  @override
  State<DynamicPaymentScreen> createState() => _DynamicPaymentScreenState();
}

class _DynamicPaymentScreenState extends State<DynamicPaymentScreen> {
  bool _termsAccepted = false;

  String _getAdTypeLabel(String adType, AppLocalizations l10n) {
    switch (adType) {
      case 'topBanner':
        return l10n.topBanner;
      case 'thinBanner':
        return l10n.thinBanner;
      case 'marketBanner':
        return l10n.marketBanner;
      default:
        return adType;
    }
  }

  String _getDurationLabel(String duration, AppLocalizations l10n) {
    switch (duration) {
      case 'oneWeek':
        return l10n.oneWeek;
      case 'twoWeeks':
        return l10n.twoWeeks;
      case 'oneMonth':
        return l10n.oneMonth;
      default:
        return duration;
    }
  }

  Color _getAdTypeColor(String adType) {
    switch (adType) {
      case 'topBanner':
        return const Color(0xFF667EEA);
      case 'thinBanner':
        return const Color(0xFFED8936);
      case 'marketBanner':
        return const Color(0xFF9F7AEA);
      default:
        return const Color(0xFF667EEA);
    }
  }

  IconData _getAdTypeIcon(String adType) {
    switch (adType) {
      case 'topBanner':
        return Icons.view_carousel_rounded;
      case 'thinBanner':
        return Icons.view_week_rounded;
      case 'marketBanner':
        return Icons.grid_view_rounded;
      default:
        return Icons.ad_units_rounded;
    }
  }

  void _proceedToPayment() {
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pleaseAcceptTerms),
          backgroundColor: const Color(0xFFE53E3E),
        ),
      );
      return;
    }

    // TODO: Navigate to payment screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IsbankAdsImagesPaymentScreen(
          submissionId: widget.submissionId,
          paymentLink: widget.paymentLink,
          price: widget.price,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adTypeColor = _getAdTypeColor(widget.adType);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1A1B23) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A202C),
        title: Text(
          l10n.paymentSummary,
          style: GoogleFonts.figtree(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A202C),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          adTypeColor.withOpacity(0.1),
                          adTypeColor.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: adTypeColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: adTypeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getAdTypeIcon(widget.adType),
                            color: adTypeColor,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.adPayment,
                                style: GoogleFonts.figtree(
                                  fontSize: 14,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.shopName,
                                style: GoogleFonts.figtree(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1A202C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Ad Preview
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1A1B23), const Color(0xFF2D3748)]
                            : [Colors.white, const Color(0xFFFAFBFC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withOpacity(0.15)
                              : const Color(0xFF64748B).withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.preview_rounded,
                                size: 20,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.adPreview,
                                style: GoogleFonts.figtree(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1A202C),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                          child: AspectRatio(
                            aspectRatio: _getAspectRatio(widget.adType),
                            child: CachedNetworkImage(
                              imageUrl: widget.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF7FAFC),
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF7FAFC),
                                child: const Icon(Icons.error_outline_rounded),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Details Card
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1A1B23), const Color(0xFF2D3748)]
                            : [Colors.white, const Color(0xFFFAFBFC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withOpacity(0.15)
                              : const Color(0xFF64748B).withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.orderDetails,
                          style: GoogleFonts.figtree(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1A202C),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Ad Type
                        _buildDetailRow(
                          l10n.adType,
                          _getAdTypeLabel(widget.adType, l10n),
                          Icons.ad_units_rounded,
                          adTypeColor,
                          isDark,
                        ),
                        const SizedBox(height: 12),

                        // Duration
                        _buildDetailRow(
                          l10n.duration,
                          _getDurationLabel(widget.duration, l10n),
                          Icons.access_time_rounded,
                          const Color(0xFF667EEA),
                          isDark,
                        ),
                        const SizedBox(height: 12),

                        // Shop
                        _buildDetailRow(
                          l10n.shop,
                          widget.shopName,
                          Icons.store_rounded,
                          const Color(0xFF9F7AEA),
                          isDark,
                        ),

                        const SizedBox(height: 20),
                        Divider(
                          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(height: 20),

                        // Price Breakdown
                        Text(
                          l10n.priceBreakdown,
                          style: GoogleFonts.figtree(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1A202C),
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildPriceRow(
                          l10n.adCost,
                          widget.price,
                          isDark,
                        ),
                        const SizedBox(height: 12),

                        _buildPriceRow(
                          l10n.tax,
                          widget.price * 0.20,
                          isDark,
                          isSubtext: true,
                        ),

                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF38A169).withOpacity(0.1),
                                const Color(0xFF38A169).withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF38A169).withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.totalAmount,
                                style: GoogleFonts.figtree(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF38A169),
                                ),
                              ),
                              Text(
                                '${(widget.price * 1.20).toStringAsFixed(2)} TL',
                                style: GoogleFonts.figtree(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF38A169),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Terms and Conditions
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A1B23)
                          : const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _termsAccepted,
                            onChanged: (value) {
                              setState(() {
                                _termsAccepted = value ?? false;
                              });
                            },
                            activeColor: const Color(0xFF38A169),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.acceptTermsAndConditions,
                            style: GoogleFonts.figtree(
                              fontSize: 13,
                              color: isDark ? const Color(0xFFA0AAB8) : const Color(0xFF4A5568),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          // Bottom Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1B23) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _proceedToPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38A169),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payment_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l10n.continueToPayment,
                        style: GoogleFonts.figtree(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.figtree(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.figtree(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A202C),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(
    String label,
    double amount,
    bool isDark, {
    bool isSubtext = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.figtree(
            fontSize: isSubtext ? 13 : 14,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        Text(
          '${amount.toStringAsFixed(2)} TL',
          style: GoogleFonts.figtree(
            fontSize: isSubtext ? 13 : 14,
            fontWeight: isSubtext ? FontWeight.w500 : FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A202C),
          ),
        ),
      ],
    );
  }

  double _getAspectRatio(String adType) {
    switch (adType) {
      case 'topBanner':
        return 16 / 9;
      case 'thinBanner':
        return 21 / 9;
      case 'marketBanner':
        return 1;
      default:
        return 16 / 9;
    }
  }
}
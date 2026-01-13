// lib/widgets/product_detail/product_detail_description.dart

import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/translation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductDetailDescription extends StatefulWidget {
  final Product product;

  const ProductDetailDescription({Key? key, required this.product})
      : super(key: key);

  @override
  _ProductDetailDescriptionState createState() =>
      _ProductDetailDescriptionState();
}

class _ProductDetailDescriptionState extends State<ProductDetailDescription> {
  String? _translatedDescription;
  bool _isTranslating = false;
  bool _isTranslated = false;

  Future<void> _translateDescription() async {
    setState(() {
      _isTranslating = true;
    });

    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final cacheKey = "translated_desc_${widget.product.id}_$languageCode";

    try {
      // Check SharedPreferences cache first (persisted cache)
      final prefs = await SharedPreferences.getInstance();
      final cachedTranslation = prefs.getString(cacheKey);

      if (cachedTranslation != null && cachedTranslation.isNotEmpty) {
        setState(() {
          _translatedDescription = cachedTranslation;
          _isTranslated = true;
          _isTranslating = false;
        });
        return;
      }

      // Use the secure translation service
      final translationService = TranslationService();
      final translation = await translationService.translate(
        widget.product.description,
        languageCode,
      );

      // Save to persistent cache
      await prefs.setString(cacheKey, translation);

      setState(() {
        _translatedDescription = translation;
        _isTranslated = true;
        _isTranslating = false;
      });
    } on RateLimitException catch (e) {
      setState(() {
        _isTranslating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.retryAfter != null
                ? 'Too many requests. Try again in ${e.retryAfter}s'
                : 'Translation limit reached. Try again later.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on TranslationException catch (e) {
      setState(() {
        _isTranslating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translationFailed)),
        );
      }
      debugPrint('Translation Error: $e');
    } catch (e) {
      setState(() {
        _isTranslating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translationFailed)),
        );
      }
      debugPrint('Translation Error: $e');
    }
  }

  void _resetTranslation() {
    setState(() {
      _isTranslated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (widget.product.description.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final displayDescription = _isTranslated
        ? (_translatedDescription ?? widget.product.description)
        : widget.product.description;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color.fromARGB(255, 40, 38, 59)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  l10n.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.orange,
                      ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isTranslating
                      ? null
                      : () {
                          if (_isTranslated) {
                            _resetTranslation();
                          } else {
                            if (_translatedDescription != null) {
                              setState(() {
                                _isTranslated = true;
                              });
                            } else {
                              _translateDescription();
                            }
                          }
                        },
                  child: Row(
                    children: [
                      Icon(
                        Icons.public,
                        size: 16,
                        color: Colors.grey,
                        semanticLabel:
                            _isTranslated ? l10n.seeOriginal : l10n.translate,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isTranslated ? l10n.seeOriginal : l10n.translate,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            _isTranslating
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.translating,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 13,
                                  ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    displayDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                        ),
                  ),
          ],
        ),
      ),
    );
  }
}
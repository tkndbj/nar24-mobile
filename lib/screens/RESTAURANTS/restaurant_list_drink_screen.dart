import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../generated/l10n/app_localizations.dart';

class RestaurantListDrinkScreen extends StatefulWidget {
  final String restaurantId;
  final String? editId;

  const RestaurantListDrinkScreen({
    Key? key,
    required this.restaurantId,
    this.editId,
  }) : super(key: key);

  @override
  State<RestaurantListDrinkScreen> createState() =>
      _RestaurantListDrinkScreenState();
}

class _RestaurantListDrinkScreenState extends State<RestaurantListDrinkScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();

  bool _saving = false;
  bool _loadingDrink = false;
  final Map<String, String> _errors = {};

  bool get _isEditMode => widget.editId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) _fetchDrink();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ── Fetch existing drink for edit mode ──────────────────────────────────

  Future<void> _fetchDrink() async {
    setState(() => _loadingDrink = true);
    try {
      final snap =
          await _firestore.collection('drinks').doc(widget.editId).get();
      if (snap.exists && mounted) {
        final data = snap.data()!;
        _nameController.text = data['name'] as String? ?? '';
        _priceController.text = (data['price'] as num?)?.toString() ?? '';
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(AppLocalizations.of(context).updateError, isError: true);
      }
    } finally {
      if (mounted) setState(() => _loadingDrink = false);
    }
  }

  // ── Validation ──────────────────────────────────────────────────────────

  bool _validate() {
    final l10n = AppLocalizations.of(context);
    final errors = <String, String>{};

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      errors['name'] = l10n.drinkNameRequired;
    } else if (name.length < 2) {
      errors['name'] = l10n.drinkNameMinLength;
    }

    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      errors['price'] = l10n.priceRequired;
    } else if ((double.tryParse(priceText) ?? 0) <= 0) {
      errors['price'] = l10n.pricePositive;
    }

    setState(() {
      _errors.clear();
      _errors.addAll(errors);
    });
    return errors.isEmpty;
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    if (!_validate()) return;

    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);

    try {
      final drinkData = {
        'name': _nameController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
      };

      if (_isEditMode) {
        await _firestore
            .collection('drinks')
            .doc(widget.editId)
            .update(drinkData);
        if (mounted) _showSnackBar(l10n.drinkUpdateSuccess, isError: false);
      } else {
        await _firestore.collection('drinks').add({
          ...drinkData,
          'restaurantId': widget.restaurantId,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) _showSnackBar(l10n.drinkAddSuccess, isError: false);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          _isEditMode ? l10n.updateError : l10n.drinkAddError,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      backgroundColor: isError ? Colors.red[600] : Colors.green[600],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors.remove(field));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121020) : const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.grey[700],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditMode ? l10n.editDrinkTitle : l10n.addDrinkTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            Text(
              _isEditMode ? l10n.editDrinkSubtitle : l10n.addDrinkSubtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
      body:
          _loadingDrink ? _buildLoadingState(isDark) : _buildForm(isDark, l10n),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade200;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(bool isDark, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Drink Details Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.grey.withOpacity(0.12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section header
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.local_drink_outlined,
                          size: 14, color: Color(0xFFFF6200)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.drinkDetails,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Drink Name
                Text(
                  l10n.drinkName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  onChanged: (_) => _clearError('name'),
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                  decoration: _inputDecoration(
                    hint: l10n.drinkNamePlaceholder,
                    error: _errors['name'],
                    isDark: isDark,
                  ),
                ),
                if (_errors['name'] != null) ...[
                  const SizedBox(height: 4),
                  Text(_errors['name']!,
                      style: TextStyle(fontSize: 11, color: Colors.red[500])),
                ],

                const SizedBox(height: 16),

                // Price
                Text(
                  l10n.price,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _priceController,
                  onChanged: (_) => _clearError('price'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                  decoration: _inputDecoration(
                    hint: '0.00',
                    error: _errors['price'],
                    isDark: isDark,
                    prefix: Icon(Icons.attach_money_rounded,
                        size: 16, color: Colors.grey[300]),
                    suffix: Text('TL',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[400])),
                  ),
                ),
                if (_errors['price'] != null) ...[
                  const SizedBox(height: 4),
                  Text(_errors['price']!,
                      style: TextStyle(fontSize: 11, color: Colors.red[500])),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Submit Button ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _handleSubmit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.local_drink_outlined, size: 16),
              label: Text(
                _saving
                    ? (_isEditMode ? l10n.updating : l10n.saving)
                    : (_isEditMode ? l10n.updateDrink : l10n.addDrinkSave),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6200),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFFFF6200).withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    String? error,
    required bool isDark,
    Widget? prefix,
    Widget? suffix,
  }) {
    final hasError = error != null;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[300]),
      prefixIcon: prefix,
      suffixIcon: suffix != null
          ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix)
          : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? Colors.red[300]! : Colors.grey.withOpacity(0.2),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? Colors.red[300]! : Colors.grey.withOpacity(0.2),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? Colors.red[400]! : const Color(0xFFFF6200),
          width: 1.5,
        ),
      ),
    );
  }
}

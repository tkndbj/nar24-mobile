import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../constants/foodData.dart';
import '../../constants/foodExtras.dart';
import '../../utils/food_localization.dart';
import '../../../utils/image_compression_utils.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class RestaurantListFoodScreen extends StatefulWidget {
  final String restaurantId;
  final String? editFoodId; // non-null → edit mode

  const RestaurantListFoodScreen({
    Key? key,
    required this.restaurantId,
    this.editFoodId,
  }) : super(key: key);

  bool get isEditMode => editFoodId != null;

  @override
  State<RestaurantListFoodScreen> createState() =>
      _RestaurantListFoodScreenState();
}

class _RestaurantListFoodScreenState extends State<RestaurantListFoodScreen> {
  // ── Controllers ──────────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _prepTimeController = TextEditingController();
  final _scrollController = ScrollController();

  // ── Form state ────────────────────────────────────────────────────────────
  String _category = '';
  String _foodType = '';
  Map<String, double> _selectedExtras = {}; // extra key → price
  Map<String, String> _extrasRawText = {}; // extra key → raw input text
  File? _imageFile;
  String? _existingImageUrl;
  bool _isCompressing = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _saving = false;
  bool _loadingFood = false;
  Map<String, String> _errors = {};

  // ── Focus nodes ───────────────────────────────────────────────────────────
  final _nameFocus = FocusNode();
  final _descFocus = FocusNode();
  final _priceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) _fetchFood();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _prepTimeController.dispose();
    _scrollController.dispose();
    _nameFocus.dispose();
    _descFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  // ── Derived data ──────────────────────────────────────────────────────────

  List<String> get _availableFoodTypes => _category.isNotEmpty
      ? (FoodCategoryData.kFoodTypes[_category] ?? [])
      : [];

  List<String> get _availableExtras =>
      _category.isNotEmpty ? (FoodExtrasData.kExtras[_category] ?? []) : [];

  // ── Fetch existing food (edit mode) ───────────────────────────────────────

  Future<void> _fetchFood() async {
    setState(() => _loadingFood = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('foods')
          .doc(widget.editFoodId)
          .get();

      if (!mounted || !snap.exists) return;
      final d = snap.data()!;

      _nameController.text = d['name'] as String? ?? '';
      _descController.text = d['description'] as String? ?? '';
      _priceController.text = (d['price'] as num?)?.toString() ?? '';
      _prepTimeController.text =
          (d['preparationTime'] as num?)?.toString() ?? '';

      final newCategory = d['foodCategory'] as String? ?? '';
      final newType = d['foodType'] as String? ?? '';

      // Rebuild extras map from [{name, price}] array
      final Map<String, double> extrasMap = {};
      final rawExtras = d['extras'] as List? ?? [];
      for (final ex in rawExtras) {
        if (ex is Map<String, dynamic>) {
          final name = ex['name'] as String? ?? '';
          final price = (ex['price'] as num?)?.toDouble() ?? 0;
          if (name.isNotEmpty) extrasMap[name] = price;
        } else if (ex is String && ex.isNotEmpty) {
          extrasMap[ex] = 0; // legacy plain-string extras
        }
      }

      final existingUrl = d['imageUrl'] as String?;

      // Build raw text map from extras for editing
      final Map<String, String> rawTextMap = {};
      for (final entry in extrasMap.entries) {
        rawTextMap[entry.key] = entry.value == 0
            ? ''
            : (entry.value == entry.value.truncateToDouble()
                ? entry.value.toInt().toString()
                : entry.value.toString());
      }

      setState(() {
        _category = newCategory;
        _foodType = newType;
        _selectedExtras = extrasMap;
        _extrasRawText = rawTextMap;
        _existingImageUrl = existingUrl;
        _loadingFood = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingFood = false);
      _showSnackBar(AppLocalizations.of(context).updateError, isError: true);
    }
  }

  // ── Image picker ──────────────────────────────────────────────────────────

Future<void> _pickImage() async {
  FocusScope.of(context).unfocus();
  final picker = ImagePicker();
  final picked =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
  if (picked == null || !mounted) return;

  final file = File(picked.path);
  final fileSize = await file.length();

  const maxBytes = 20 * 1024 * 1024; // 20 MB
  if (fileSize > maxBytes) {
    _showSnackBar(AppLocalizations.of(context).fileSizeError, isError: true);
    return;
  }

  setState(() {
    _errors.remove('image');
    _isCompressing = true;
  });

  try {
    final compressed = await ImageCompressionUtils.compressProductImage(file);
    if (!mounted) return;
    setState(() {
      _imageFile = compressed ?? file;
      _isCompressing = false;
    });
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _imageFile = file;
      _isCompressing = false;
    });
  }
}

  // ── Validation ────────────────────────────────────────────────────────────

  bool _validate() {
    final l10n = AppLocalizations.of(context);
    final newErrors = <String, String>{};

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      newErrors['name'] = l10n.nameRequired;
    } else if (name.length < 2) {
      newErrors['name'] = l10n.nameMinLength;
    }

    final desc = _descController.text.trim();
    if (desc.isNotEmpty && desc.length < 10) {
      newErrors['description'] = l10n.descriptionMinLength;
    }

    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      newErrors['price'] = l10n.priceRequired;
    } else if ((double.tryParse(priceText) ?? 0) <= 0) {
      newErrors['price'] = l10n.pricePositive;
    }

    if (_category.isEmpty) newErrors['category'] = l10n.categoryRequired;
    if (_foodType.isEmpty) newErrors['foodType'] = l10n.typeRequired;

    setState(() => _errors = newErrors);
    return newErrors.isEmpty;
  }

  // ── Upload image ──────────────────────────────────────────────────────────

  Future<String> _uploadImage(File file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'foods/$uid/${widget.restaurantId}/${timestamp}_food.jpg';
    final ref = FirebaseStorage.instance.ref(path);

    final task = ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final snap = await task;
    return snap.ref.getDownloadURL();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    setState(() => _saving = true);
    try {
      // 1. Resolve image URL
      String imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadImage(_imageFile!);
      } else if (widget.isEditMode && _existingImageUrl != null) {
        imageUrl = _existingImageUrl!;
      } else {
        imageUrl = '';
      }

      // 2. Build food document
      final foodData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'foodCategory': _category,
        'foodType': _foodType,
        'imageUrl': imageUrl,
        'preparationTime': _prepTimeController.text.trim().isNotEmpty
            ? int.tryParse(_prepTimeController.text.trim())
            : null,
        'extras': _selectedExtras.entries
            .map((e) => {'name': e.key, 'price': e.value})
            .toList(),
      };

      final firestore = FirebaseFirestore.instance;
      if (widget.isEditMode && widget.editFoodId != null) {
        await firestore
            .collection('foods')
            .doc(widget.editFoodId)
            .update(foodData);
        if (mounted) {
          _showSnackBar(AppLocalizations.of(context).updateSuccess,
              isError: false);
        }
      } else {
        await firestore.collection('foods').add({
          ...foodData,
          'restaurantId': widget.restaurantId,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          _showSnackBar(AppLocalizations.of(context).foodAddedSuccess,
              isError: false);
        }
      }

      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        widget.isEditMode
            ? AppLocalizations.of(context).updateError
            : AppLocalizations.of(context).foodAddError,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(fontSize: 13)),
      backgroundColor: isError ? Colors.red[600] : Colors.green[600],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _getCategoryName(String key) {
    return localizeCategory(key, AppLocalizations.of(context));
  }

  String _getFoodTypeName(String key) {
    return localizeFoodType(key, AppLocalizations.of(context));
  }

  String _getExtraName(String key) {
    return localizeExtra(key, AppLocalizations.of(context));
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors.remove(field));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    if (_loadingFood) return _buildLoadingScaffold(isDark, l10n);

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: isDark ? null : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditMode ? l10n.editFoodTitle : l10n.addFoodTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.isEditMode ? l10n.editFoodSubtitle : l10n.addFoodSubtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            children: [
              _buildImageSection(isDark, l10n),
              const SizedBox(height: 12),
              _buildDetailsSection(isDark, l10n),
              const SizedBox(height: 12),
              _buildCategorySection(isDark, l10n),
              const SizedBox(height: 12),
              if (_foodType.isNotEmpty && _availableExtras.isNotEmpty) ...[
                _buildExtrasSection(isDark, l10n),
                const SizedBox(height: 12),
              ],
              _buildPrepTimeSection(isDark, l10n),
              const SizedBox(height: 20),
              _buildSubmitButton(l10n),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Image Section ─────────────────────────────────────────────────────────

  Widget _buildImageSection(bool isDark, AppLocalizations l10n) {
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.image_outlined,
            iconBg: const Color(0xFFFFF7ED),
            iconColor: const Color(0xFFEA580C),
            title: l10n.foodImage,
            badge: l10n.optional,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _isCompressing ? null : _pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 140),
              decoration: BoxDecoration(
                color:
                    isDark ? Colors.white.withOpacity(0.04) : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _errors.containsKey('image')
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4),
                  width: 1.5,
                  style: (_imageFile == null && _existingImageUrl == null)
                      ? BorderStyle.solid
                      : BorderStyle.solid,
                ),
              ),
              child: _isCompressing
                  ? _buildCompressingIndicator(l10n)
                  : (_imageFile != null || _existingImageUrl != null)
                      ? _buildImagePreview(isDark, l10n)
                      : _buildImagePlaceholder(l10n),
            ),
          ),
          if (_errors.containsKey('image')) ...[
            const SizedBox(height: 6),
            Text(_errors['image']!,
                style: TextStyle(fontSize: 11, color: Colors.red[500])),
          ],
        ],
      ),
    );
  }

  Widget _buildCompressingIndicator(AppLocalizations l10n) {
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFFF6200),
              ),
            ),
            const SizedBox(height: 10),
            Text(l10n.compressing),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(bool isDark, AppLocalizations l10n) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: _imageFile != null
              ? Image.file(
                  _imageFile!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                )
              : Image.network(
                  _existingImageUrl!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(
                          height: 180,
                          color: Colors.grey[100],
                          child: const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFFF6200))),
                        ),
                ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: Colors.black.withOpacity(0.15),
            ),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.changeImage,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePlaceholder(AppLocalizations l10n) {
    return SizedBox(
      height: 140,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_outlined,
              size: 32, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 8),
          Text(
            l10n.imageHint,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // ── Details Section ───────────────────────────────────────────────────────

  Widget _buildDetailsSection(bool isDark, AppLocalizations l10n) {
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.description_outlined,
            iconBg: const Color(0xFFFFF7ED),
            iconColor: const Color(0xFFEA580C),
            title: l10n.foodDetails,
            isDark: isDark,
          ),
          const SizedBox(height: 16),

          // Name
          _FieldLabel(l10n.foodName),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _nameController,
            focusNode: _nameFocus,
            hint: l10n.foodNamePlaceholder,
            errorKey: 'name',
            isDark: isDark,
            onChanged: (v) {
              // Title-case: capitalise first letter of each word
              final titled = v
                  .split(' ')
                  .map((w) =>
                      w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
                  .join(' ');
              if (titled != v) {
                _nameController.value = _nameController.value.copyWith(
                  text: titled,
                  selection: TextSelection.collapsed(offset: titled.length),
                );
              }
              _clearError('name');
            },
          ),
          const SizedBox(height: 14),

          // Description
          Row(
            children: [
              Text(l10n.description,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[500])),
              const SizedBox(width: 6),
              _BadgeLabel(l10n.optional),
            ],
          ),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _descController,
            focusNode: _descFocus,
            hint: l10n.foodDescriptionPlaceholder,
            errorKey: 'description',
            isDark: isDark,
            maxLines: 3,
            onChanged: (v) {
              // Capitalise first letter
              if (v.isNotEmpty) {
                final cap = v[0].toUpperCase() + v.substring(1);
                if (cap != v) {
                  _descController.value = _descController.value.copyWith(
                    text: cap,
                    selection: TextSelection.collapsed(offset: cap.length),
                  );
                }
              }
              _clearError('description');
            },
          ),
          const SizedBox(height: 14),

          // Price
          _FieldLabel(l10n.price),
          const SizedBox(height: 6),
          _buildPriceField(isDark, l10n),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required String errorKey,
    required bool isDark,
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    final hasError = _errors.containsKey(errorKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(
              fontSize: 13, color: isDark ? Colors.white : Colors.grey[800]),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey[400]),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError ? Colors.red[400]! : const Color(0xFFFF6200),
                  width: 2),
            ),
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 5),
          Text(_errors[errorKey]!,
              style: TextStyle(fontSize: 11, color: Colors.red[500])),
        ],
      ],
    );
  }

  Widget _buildPriceField(bool isDark, AppLocalizations l10n) {
    final hasError = _errors.containsKey('price');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _priceController,
          focusNode: _priceFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
          ],
          onChanged: (_) => _clearError('price'),
          style: TextStyle(
              fontSize: 13, color: isDark ? Colors.white : Colors.grey[800]),
          decoration: InputDecoration(
            hintText: l10n.pricePlaceholder,
            hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey[400]),
            prefixIcon: Icon(Icons.attach_money_rounded,
                size: 18, color: isDark ? const Color(0xFFD1D5DB) : Colors.grey[500]),
            suffixText: l10n.currency,
            suffixStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[400] : Colors.grey[500]),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError ? Colors.red[400]! : const Color(0xFFFF6200),
                  width: 2),
            ),
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 5),
          Text(_errors['price']!,
              style: TextStyle(fontSize: 11, color: Colors.red[500])),
        ],
      ],
    );
  }

  // ── Category Section ──────────────────────────────────────────────────────

  Widget _buildCategorySection(bool isDark, AppLocalizations l10n) {
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.restaurant_menu_outlined,
            iconBg: const Color(0xFFFFF7ED),
            iconColor: const Color(0xFFEA580C),
            title: l10n.foodCategory,
            isDark: isDark,
          ),
          const SizedBox(height: 16),

          // Category dropdown
          _FieldLabel(l10n.foodCategory),
          const SizedBox(height: 6),
          _buildDropdown(
            hint: l10n.selectCategory,
            value: _category.isEmpty ? null : _category,
            items: FoodCategoryData.kCategories
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(_getCategoryName(c),
                          style: TextStyle(fontSize: 13)),
                    ))
                .toList(),
            isDark: isDark,
            hasError: _errors.containsKey('category'),
            errorText: _errors['category'],
            onChanged: (v) {
              setState(() {
                _category = v ?? '';
                _foodType = '';
                _selectedExtras = {};
                _extrasRawText = {};
                _errors.remove('category');
                _errors.remove('foodType');
              });
            },
          ),
          const SizedBox(height: 14),

          // Food type dropdown
          _FieldLabel(l10n.foodType),
          const SizedBox(height: 6),
          _buildDropdown(
            hint: _category.isNotEmpty
                ? l10n.selectType
                : l10n.selectCategoryFirst,
            value: _foodType.isEmpty ? null : _foodType,
            items: _availableFoodTypes
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(_getFoodTypeName(t),
                          style: TextStyle(fontSize: 13)),
                    ))
                .toList(),
            isDark: isDark,
            enabled: _category.isNotEmpty,
            hasError: _errors.containsKey('foodType'),
            errorText: _errors['foodType'],
            onChanged: (v) {
              setState(() {
                _foodType = v ?? '';
                _errors.remove('foodType');
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required bool isDark,
    required void Function(String?) onChanged,
    bool enabled = true,
    bool hasError = false,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError
                      ? Colors.red[300]!
                      : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hasError ? Colors.red[400]! : const Color(0xFFFF6200),
                  width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withOpacity(0.12)),
            ),
            filled: true,
            fillColor: !enabled
                ? (isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50])
                : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
          ),
          hint: Text(hint,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey[500])),
          style: TextStyle(
              fontSize: 13, color: isDark ? Colors.white : Colors.grey[800]),
          dropdownColor: isDark ? const Color(0xFF1E1B2E) : Colors.white,
          items: enabled ? items : [],
          onChanged: enabled ? onChanged : null,
        ),
        if (hasError && errorText != null) ...[
          const SizedBox(height: 5),
          Text(errorText,
              style: TextStyle(fontSize: 11, color: Colors.red[500])),
        ],
      ],
    );
  }

  // ── Extras Section ────────────────────────────────────────────────────────

  Widget _buildExtrasSection(bool isDark, AppLocalizations l10n) {
    final selectedCount = _selectedExtras.length;
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionHeader(
                icon: Icons.checklist_rounded,
                iconBg: const Color(0xFFFFF7ED),
                iconColor: const Color(0xFFEA580C),
                title: l10n.extras,
                badge: l10n.optional,
                isDark: isDark,
                compact: true,
              ),
              if (selectedCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n.extrasSelected(selectedCount),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEA580C),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.extrasHint,
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: _availableExtras.map((extra) {
              final isSelected = _selectedExtras.containsKey(extra);
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 72) / 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toggle chip
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedExtras.remove(extra);
                            _extrasRawText.remove(extra);
                          } else {
                            _selectedExtras[extra] = 0;
                            _extrasRawText[extra] = '';
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFF7ED)
                              : (isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFDBA74)
                                : isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              isSelected ? '✓  ' : '+  ',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? const Color(0xFFEA580C)
                                    : Colors.grey[400],
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _getExtraName(extra),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFFEA580C)
                                      : (isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[600]),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Price input when selected
                    if (isSelected) ...[
                      const SizedBox(height: 5),
                      TextField(
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            // Normalize comma to dot
                            final normalized =
                                newValue.text.replaceAll(',', '.');
                            // Allow up to 4 digits, optional dot, up to 2 decimals
                            if (normalized.isEmpty ||
                                RegExp(r'^\d{0,4}\.?\d{0,2}$')
                                    .hasMatch(normalized)) {
                              return newValue.copyWith(text: normalized);
                            }
                            return oldValue;
                          }),
                        ],
                        controller: TextEditingController(
                          text: _extrasRawText[extra] ?? '',
                        )..selection = TextSelection.collapsed(
                            offset: (_extrasRawText[extra] ?? '').length),
                        onChanged: (v) {
                          _extrasRawText[extra] = v;
                          _selectedExtras[extra] = double.tryParse(v) ?? 0;
                        },
                        style: TextStyle(fontSize: 11),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: TextStyle(
                              fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                          suffixText: l10n.currency,
                          suffixStyle: TextStyle(
                              fontSize: 10, color: Colors.grey[400]),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color:
                                    const Color(0xFFFDBA74).withOpacity(0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color:
                                    const Color(0xFFFDBA74).withOpacity(0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFFF6200), width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withOpacity(0.04)
                              : const Color(0xFFFFF7ED).withOpacity(0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Prep Time Section ─────────────────────────────────────────────────────

  Widget _buildPrepTimeSection(bool isDark, AppLocalizations l10n) {
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.access_time_rounded,
            iconBg: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[50]!,
            iconColor: Colors.grey[500]!,
            title: l10n.preparationTime,
            badge: l10n.optional,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _prepTimeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
                fontSize: 13, color: isDark ? Colors.white : Colors.grey[800]),
            decoration: InputDecoration(
              hintText: l10n.preparationTimePlaceholder,
              hintStyle:
                  TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey[400]),
              prefixIcon: Icon(Icons.access_time_rounded,
                  size: 18, color: isDark ? const Color(0xFFD1D5DB) : Colors.grey[500]),
              suffixText: l10n.minutes,
              suffixStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[500]),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.grey.withOpacity(0.25) : Colors.grey.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFFF6200), width: 2),
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit Button ─────────────────────────────────────────────────────────

  Widget _buildSubmitButton(AppLocalizations l10n) {
    return ElevatedButton(
      onPressed: _saving ? null : _handleSubmit,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF6200),
        disabledBackgroundColor: const Color(0xFFFF6200).withOpacity(0.5),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: _saving
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.isEditMode ? l10n.updatingFood : l10n.savingFood,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.restaurant_menu_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  widget.isEditMode ? l10n.updateFood : l10n.saveFood,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
    );
  }

  // ── Loading scaffold ──────────────────────────────────────────────────────

  Widget _buildLoadingScaffold(bool isDark, AppLocalizations l10n) {
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: isDark ? null : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Container(
              height: 18,
              width: 140,
              decoration: BoxDecoration(
                  color: base, borderRadius: BorderRadius.circular(6))),
        ),
      ),
      body: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image card skeleton
            Container(
              height: 180,
              decoration: BoxDecoration(
                  color: base, borderRadius: BorderRadius.circular(16)),
            ),
            const SizedBox(height: 12),
            // Details card skeleton
            Container(
              height: 200,
              decoration: BoxDecoration(
                  color: base, borderRadius: BorderRadius.circular(16)),
            ),
            const SizedBox(height: 12),
            // Category card skeleton
            Container(
              height: 140,
              decoration: BoxDecoration(
                  color: base, borderRadius: BorderRadius.circular(16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.12),
        ),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? badge;
  final bool isDark;
  final bool compact;

  const _SectionHeader({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.badge,
    required this.isDark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 6),
          _BadgeLabel(badge!),
        ],
      ],
    );
  }
}

class _BadgeLabel extends StatelessWidget {
  final String text;
  const _BadgeLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey[400]),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.grey[500],
      ),
    );
  }
}

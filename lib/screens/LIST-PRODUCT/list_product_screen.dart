import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../models/product.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../widgets/listproduct/delivery_options_accordion.dart';
import '../../widgets/listproduct/media_picker_widget.dart';
import '../../widgets/listproduct/product_info_form.dart';
import '../../models/list_product_flow_model.dart';
import '../../utils/attribute_route_mapper.dart';
import '../../utils/image_compression_utils.dart';

/// Custom formatter for price input that:
/// - Allows digits, dot, and comma
/// - Converts comma to dot
/// - Limits to 2 decimal places
class _PriceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Replace comma with dot
    String text = newValue.text.replaceAll(',', '.');

    // Remove any characters that aren't digits or dots
    text = text.replaceAll(RegExp(r'[^\d.]'), '');

    // Ensure only one dot
    int dotCount = '.'.allMatches(text).length;
    if (dotCount > 1) {
      int firstDotIndex = text.indexOf('.');
      text = text.substring(0, firstDotIndex + 1) +
          text.substring(firstDotIndex + 1).replaceAll('.', '');
    }

    // Limit to 2 decimal places
    if (text.contains('.')) {
      List<String> parts = text.split('.');
      if (parts.length == 2 && parts[1].length > 2) {
        text = '${parts[0]}.${parts[1].substring(0, 2)}';
      }
    }

    // Calculate new cursor position
    int newCursorPos = newValue.selection.end;
    int oldLength = newValue.text.length;
    int newLength = text.length;
    newCursorPos = newCursorPos - (oldLength - newLength);
    if (newCursorPos < 0) newCursorPos = 0;
    if (newCursorPos > text.length) newCursorPos = text.length;

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }
}

class ListProductScreen extends StatefulWidget {
  final File? imageFile;
  final String? category;
  final String? shopId;
  final Product? existingProduct;
  final bool isFromArchivedCollection;

  const ListProductScreen({
    Key? key,
    this.imageFile,
    this.category,
    this.shopId,
    this.existingProduct,
    this.isFromArchivedCollection = false,
  }) : super(key: key);

  @override
  _ListProductScreenState createState() => _ListProductScreenState();
}

class _ListProductScreenState extends State<ListProductScreen> {
  String? _shopId;
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;


  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isCompressing = false;
int _compressingCurrent = 0;
int _compressingTotal = 0;

  // Dynamic attributes map - all specific details go here
  final Map<String, dynamic> _attributes = {};
  StreamSubscription<QuerySnapshot>? _flowsSubscription;
  // Core product fields
  String? _selectedCategory;
  String? _selectedSubcategory;
  String? _selectedSubsubcategory;
  String? _selectedBrand;
  String? _selectedCondition;
  Map<String, Map<String, dynamic>> _selectedColorImages = {};
  List<XFile> _videoFiles = [];
  List<XFile> _imageFiles = [];
  XFile? _newVideoFile;

  bool get isEditMode => widget.existingProduct != null;
  List<String> _existingImageUrls = [];

  String? _selectedDeliveryOption;


  List<ProductListingFlow> _flows = [];

  @override
  void initState() {
    super.initState();
    _shopId = widget.shopId;

    if (_shopId == null && !isEditMode) {
      _quantityController.text = '1';
    }

    _flowsSubscription = FirebaseFirestore.instance
        .collection('product_flows')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _flows =
            snap.docs.map((doc) => ProductListingFlow.fromDoc(doc)).toList();
      });
    });

    if (isEditMode) {
      _initializeForEditMode();
    } else {
      _initializeWithImageAndCategory();
    }
  }

  @override
  void dispose() {
    _flowsSubscription?.cancel();
    _titleController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  ProductListingFlow? _findMatchingFlow(String cat, String sub, String subsub) {
    final List<MapEntry<ProductListingFlow, int>> matchingFlows = [];

    for (final flow in _flows) {
      if (!flow.isActive) {
        continue;
      }

      for (final step in flow.steps.values) {
        for (final nextStep in step.nextSteps) {
          final conditions = nextStep.conditions;
          if (conditions == null) continue;

          final categoryList = conditions['category'];
          final categoryMatch =
              categoryList != null && categoryList.contains(cat);

          if (!categoryMatch) {
            continue;
          }

          final subcategoryList = conditions['subcategory'];
          bool subcategoryMatch = true;
          if (subcategoryList != null && subcategoryList.isNotEmpty) {
            subcategoryMatch = subcategoryList.contains(sub);
            if (!subcategoryMatch) {
              continue;
            }
          }

          final subSubcategoryList = conditions['subsubcategory'];
          bool subSubcategoryMatch = true;
          if (subSubcategoryList != null && subSubcategoryList.isNotEmpty) {
            subSubcategoryMatch = subSubcategoryList.contains(subsub);
            if (!subSubcategoryMatch) {
              continue;
            }
          }

          int specificity = 0;
          if (categoryList.isNotEmpty) specificity += 1;
          if (subcategoryList != null && subcategoryList.isNotEmpty)
            specificity += 10;
          if (subSubcategoryList != null && subSubcategoryList.isNotEmpty)
            specificity += 100;

          matchingFlows.add(MapEntry(flow, specificity));
          break;
        }
      }
    }

    if (matchingFlows.isEmpty) {
      return null;
    }

    matchingFlows.sort((a, b) => b.value.compareTo(a.value));

    return matchingFlows.first.key;
  }

  /// Follow `nextSteps[0]` pointers to build an ordered list of stepIds.
  List<String> _linearizeFlow(ProductListingFlow flow) {
    final List<String> out = [];
    String? cur = flow.startStepId;
    final visited = <String>{};

    while (cur != null && !visited.contains(cur)) {
      visited.add(cur);
      out.add(cur);

      if (cur == 'preview') break;

      final currentStep = flow.steps[cur];
      if (currentStep == null) {
        break;
      }

      final ns = currentStep.nextSteps;
      if (ns.isEmpty) {
        out.add('preview');
        break;
      }

      cur = ns[0].stepId;
    }

    return out;
  }

  String _formatColorDisplay() {
    final l10n = AppLocalizations.of(context);
    return AttributeLocalizationUtils.formatColorDisplay(
        _selectedColorImages, l10n);
  }

  Future<void> _initializeForEditMode() async {
    final product = widget.existingProduct!;

    setState(() {
      _titleController.text = product.productName;
      _priceController.text = product.price.toString();
      _quantityController.text = product.quantity.toString();
      _descriptionController.text = product.description;

      _selectedCategory = product.category;
      _selectedSubcategory = product.subcategory;
      _selectedSubsubcategory = product.subsubcategory;
      _selectedBrand = product.brandModel;
      _selectedCondition = product.condition;
      _selectedDeliveryOption = product.deliveryOption;

      _existingImageUrls = product.imageUrls;
      _selectedColorImages.clear();
      product.colorQuantities.forEach((color, qty) {
        _selectedColorImages[color] = {
          'quantity': qty,
          'image': null,
        };
      });

      _attributes.clear();
      final cleanedAttrs = _cleanAttributes(product.attributes);
      _attributes.addAll(cleanedAttrs);

      if (product.gender != null && product.gender!.isNotEmpty) {
        _attributes['gender'] = product.gender!;
      } else if (!_attributes.containsKey('gender') &&
          product.attributes.containsKey('gender')) {
        _attributes['gender'] = product.attributes['gender'];
      }

      if (product.productType != null)
        _attributes['productType'] = product.productType;
      if (product.clothingSizes != null)
        _attributes['clothingSizes'] = product.clothingSizes;
      if (product.clothingFit != null)
        _attributes['clothingFit'] = product.clothingFit;
      if (product.clothingTypes != null)
        _attributes['clothingTypes'] = product.clothingTypes;
      if (product.pantSizes != null)
        _attributes['pantSizes'] = product.pantSizes;
      if (product.pantFabricTypes != null)
        _attributes['pantFabricTypes'] = product.pantFabricTypes;
      if (product.footwearSizes != null)
        _attributes['footwearSizes'] = product.footwearSizes;
      if (product.jewelryMaterials != null)
        _attributes['jewelryMaterials'] = product.jewelryMaterials;
      if (product.consoleBrand != null)
        _attributes['consoleBrand'] = product.consoleBrand;
      if (product.curtainMaxWidth != null)
        _attributes['curtainMaxWidth'] = product.curtainMaxWidth;
      if (product.curtainMaxHeight != null)
        _attributes['curtainMaxHeight'] = product.curtainMaxHeight;
    });
  }

  Map<String, dynamic> _cleanAttributes(Map<String, dynamic> attributes) {
    final Map<String, dynamic> cleaned = {};

    attributes.forEach((key, value) {
      if (value != null && _isValidAttributeValue(value)) {
        if (value is List) {
          final List cleanedList = value
              .where(
                  (item) => item != null && item.toString().trim().isNotEmpty)
              .toList();
          if (cleanedList.isNotEmpty) {
            cleaned[key] = cleanedList;
          }
        } else if (value is Map) {
          final Map<String, dynamic> cleanedMap =
              _cleanAttributes(Map<String, dynamic>.from(value));
          if (cleanedMap.isNotEmpty) {
            cleaned[key] = cleanedMap;
          }
        } else if (value.toString().trim().isNotEmpty) {
          cleaned[key] = value;
        }
      }
    });

    return cleaned;
  }

  bool _isValidAttributeValue(dynamic value) {
    if (value == null) return false;

    if (value is String) {
      return value.trim().isNotEmpty;
    }

    if (value is List) {
      return value.isNotEmpty &&
          value
              .any((item) => item != null && item.toString().trim().isNotEmpty);
    }

    if (value is Map) {
      return value.isNotEmpty;
    }

    return true;
  }

  Future<void> _initializeWithImageAndCategory() async {
    if (widget.imageFile != null && widget.category != null) {
      setState(() {
        _selectedCategory = widget.category;
        _imageFiles.add(XFile(widget.imageFile!.path));
      });
    }
  }

 Future<void> _pickImages(ImageSource source) async {
  FocusScope.of(context).unfocus();
  await Future.delayed(const Duration(milliseconds: 100));

  try {
    List<XFile> picked = [];

    if (source == ImageSource.gallery) {
      picked = await ImagePicker().pickMultiImage();
    } else {
      final file = await ImagePicker().pickImage(source: ImageSource.camera);
      if (file != null) picked = [file];
    }

    if (picked.isEmpty) return;

    // ── Max image count check ──────────────────────────────────────
    const maxImages = 10;
    final currentCount = _imageFiles.length + _existingImageUrls.length;
    final remaining = maxImages - currentCount;

    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Maximum $maxImages photos allowed')),
        );
      }
      return;
    }

    if (picked.length > remaining) {
      picked = picked.take(remaining).toList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Only $remaining more photo(s) can be added. '
              'Selecting first $remaining.',
            ),
          ),
        );
      }
    }

    // ── Per-file size check (before compression) ───────────────────
    const maxFileSizeMB = 20;
    final oversized = <String>[];
    final validPicked = <XFile>[];

    for (final file in picked) {
      final bytes = await File(file.path).length();
      final mb = bytes / (1024 * 1024);
      if (mb > maxFileSizeMB) {
        oversized.add(file.name);
      } else {
        validPicked.add(file);
      }
    }

    if (oversized.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${oversized.length} file(s) exceed ${maxFileSizeMB}MB and were skipped: '
            '${oversized.join(', ')}',
          ),
        ),
      );
    }

    if (validPicked.isEmpty) return;

    // ── Compression (unchanged from before) ───────────────────────
    if (mounted) {
      setState(() {
        _isCompressing = true;
        _compressingCurrent = 0;
        _compressingTotal = validPicked.length;
      });
    }

    final compressedFiles = <XFile>[];
    const int compressionThresholdBytes = 300 * 1024; 

for (int i = 0; i < validPicked.length; i++) {
  if (mounted) setState(() => _compressingCurrent = i + 1);

  final originalFile = File(validPicked[i].path);
  final fileSize = await originalFile.length();

  if (fileSize <= compressionThresholdBytes) {
    // Already small enough — skip compression, use as-is
    compressedFiles.add(validPicked[i]);
  } else {
    final compressed = await ImageCompressionUtils.ecommerceCompress(originalFile);
    // If compression produces a larger file, fall back to original
    if (compressed != null && await compressed.length() < fileSize) {
      compressedFiles.add(XFile(compressed.path));
    } else {
      compressedFiles.add(validPicked[i]);
    }
  }
}
    if (mounted) {
      setState(() {
        _imageFiles.addAll(compressedFiles);
        _isCompressing = false;
      });
    }
  } catch (e) {
    print('Error picking/compressing images: $e');
    if (mounted) setState(() => _isCompressing = false);
  }
}

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

 Future<void> _pickVideo(ImageSource source) async {
  FocusScope.of(context).unfocus();
  await Future.delayed(const Duration(milliseconds: 100));

  const maxVideoSizeMB = 80;

  try {
    XFile? pickedFile;

    if (source == ImageSource.gallery) {
      pickedFile = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } else {
      pickedFile = await ImagePicker().pickVideo(source: ImageSource.camera);
    }

    if (pickedFile == null) return;

    // ── Size check ─────────────────────────────────────────────────
    final bytes = await File(pickedFile.path).length();
    final mb = bytes / (1024 * 1024);

    if (mb > maxVideoSizeMB) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Video exceeds ${maxVideoSizeMB}MB limit '
              '(${mb.toStringAsFixed(1)}MB). Please choose a shorter clip.',
            ),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _videoFiles = [pickedFile!];
        _newVideoFile = pickedFile;
      });
    }
  } catch (e) {
    print('Error picking video: $e');
  }

  if (mounted) setState(() {});
}

  void _removeVideo(int index) {
    setState(() {
      _videoFiles.clear();
      _newVideoFile = null;
    });
  }

  Future<void> _showCategoryPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final result = await context.push(
      '/list_category',
      extra: {
        'initialCategory': _selectedCategory,
        'initialSubcategory': _selectedSubcategory,
      },
    ) as Map<String, dynamic>?;
    if (!mounted) return;
    if (result == null) {
      return;
    }

    final newCat = result['category'] as String;
    final newSub = result['subcategory'] as String;
    final newSubSub = result['subsubcategory'] as String;

    final changed = newCat != _selectedCategory ||
        newSub != _selectedSubcategory ||
        newSubSub != _selectedSubsubcategory;
    if (changed) {
      setState(() {
        _selectedBrand = null;
        _selectedColorImages = {};
        _attributes.clear();
      });
    }

    setState(() {
      _selectedCategory = newCat;
      _selectedSubcategory = newSub;
      _selectedSubsubcategory = newSubSub;
    });

    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 200));

    await _executeProductFlow(newCat, newSub, newSubSub);
  }

  Future<void> _executeProductFlow(
      String cat, String sub, String subsub) async {
    final flow = _findMatchingFlow(cat, sub, subsub);
    if (flow == null) return;

    final stepIds = _linearizeFlow(flow);

    for (final stepId in stepIds) {
      final success = await _executeFlowStep(stepId, cat, sub, subsub);
      if (!success) {
        return;
      }
    }
  }

  Future<bool> _executeFlowStep(
      String stepId, String cat, String sub, String subsub) async {
    try {
      if (stepId == 'preview') {
        await _navigateToPreview();
        return true;
      }

      return await _executeDynamicStep(stepId, cat, sub, subsub);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _executeDynamicStep(
      String stepId, String cat, String sub, String subsub) async {
    final routePath = '/$stepId';

    try {
      FocusManager.instance.primaryFocus?.unfocus();

      final extraData = {
        'initialAttributes': Map<String, dynamic>.from(_attributes),
        'category': cat,
        'subcategory': sub,
        'subsubcategory': subsub,
        'initialBrand': _selectedBrand,
      };

      final result = await context.push(routePath, extra: extraData);
      if (!mounted) return false;
      if (result == null) return false;

      setState(() {
        if (result is Map<String, dynamic>) {
          if (result.isEmpty) {
            if (stepId == 'list_color') {
              _selectedColorImages.clear();
            }
            return;
          }

          bool isColorData = false;

          if (result.isNotEmpty) {
            isColorData = result.values.every((value) =>
                value is Map &&
                value.containsKey('image') &&
                value.containsKey('quantity'));
          }

          if (isColorData) {
            _selectedColorImages.clear();
            result.forEach((key, value) {
              if (value is Map) {
                _selectedColorImages[key] = Map<String, dynamic>.from(value);
              }
            });
          } else {
            if (result.containsKey('brand')) {
              _selectedBrand = result['brand'] as String?;
            }

            result.forEach((key, value) {
              if (key != 'brand' && value != null) {
                _attributes[key] = value;
              }
            });
          }
        } else if (result is Map<String, Map<String, dynamic>>) {
          _selectedColorImages = Map<String, Map<String, dynamic>>.from(result);
        }
      });

      return true;
    } catch (e) {
      if (e.toString().toLowerCase().contains('route')) {
        return true;
      }
      return false;
    }
  }

  String _formatAttributesDisplay() {
    final l10n = AppLocalizations.of(context);
    return AttributeLocalizationUtils.formatAttributesDisplay(
        _attributes, l10n);
  }

  Future<void> _editBrand() async {
    if (_selectedCategory == null ||
        _selectedSubcategory == null ||
        _selectedSubsubcategory == null) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    final extraData = {
      'initialAttributes': Map<String, dynamic>.from(_attributes),
      'category': _selectedCategory,
      'subcategory': _selectedSubcategory,
      'subsubcategory': _selectedSubsubcategory,
      'initialBrand': _selectedBrand,
    };

    final result = await context.push(
      AttributeRouteMapper.brandRoute,
      extra: extraData,
    );
    if (!mounted) return;
    if (result == null) return;

    setState(() {
      if (result is Map<String, dynamic>) {
        if (result.containsKey('brand')) {
          _selectedBrand = result['brand'] as String?;
        }
        result.forEach((key, value) {
          if (key != 'brand' && value != null) {
            _attributes[key] = value;
          }
        });
      }
    });
  }

  Future<void> _editColors() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final Map<String, Map<String, dynamic>>? initialColorData;
    if (_selectedColorImages.isNotEmpty) {
      initialColorData =
          Map<String, Map<String, dynamic>>.from(_selectedColorImages);
    } else {
      initialColorData = null;
    }

    Map<String, List<String>>? existingColorUrls;
    if (isEditMode && widget.existingProduct != null) {
      existingColorUrls = widget.existingProduct!.colorImages;
    }

    final result = await context.push(
      AttributeRouteMapper.colorRoute,
      extra: {
        'initialColorData': initialColorData,
        'existingColorImageUrls': existingColorUrls,
      },
    );
    if (!mounted) return;
    if (result == null) return;

    setState(() {
      if (result is Map) {
        if (result.isEmpty) {
          _selectedColorImages.clear();
          return;
        }

        bool isColorData = result.values.every((value) =>
            value is Map &&
            value.containsKey('image') &&
            value.containsKey('quantity'));

        if (isColorData) {
          _selectedColorImages.clear();
          result.forEach((key, value) {
            if (key is String && value is Map) {
              _selectedColorImages[key] = Map<String, dynamic>.from(value);
            }
          });
        }
      }
    });
  }

  Future<void> _editAttribute(String attributeKey) async {
    if (_selectedCategory == null ||
        _selectedSubcategory == null ||
        _selectedSubsubcategory == null) {
      return;
    }

    final route = AttributeRouteMapper.getRouteForAttribute(attributeKey);
    if (route == null) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final extraData = {
      'initialAttributes': Map<String, dynamic>.from(_attributes),
      'category': _selectedCategory,
      'subcategory': _selectedSubcategory,
      'subsubcategory': _selectedSubsubcategory,
      'initialBrand': _selectedBrand,
    };

    final result = await context.push(route, extra: extraData);
    if (!mounted) return;
    if (result == null) return;

    setState(() {
      if (result is Map<String, dynamic>) {
        result.forEach((key, value) {
          if (key != 'brand' && value != null) {
            _attributes[key] = value;
          }
        });
      }
    });
  }

  void _showPreparingPreviewModal() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1500),
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value * 2 * 3.14159,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00A86B), Color(0xFF00C574)],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.preview_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                l10n.preparingPreview,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.pleaseWaitWhileWeLoadYourProduct,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _navigateToPreview — NO uploads here. Builds the Product with existing
  // URLs only and passes raw files to the preview screen, which will upload
  // everything when the user taps "Confirm".
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _navigateToPreview() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null ||
        _selectedCategory!.isEmpty ||
        _selectedSubcategory == null ||
        _selectedSubcategory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.categoryRequired)),
      );
      return;
    }
    if (_imageFiles.isEmpty && _existingImageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseUploadAtLeastOnePhoto)),
      );
      return;
    }
    if (_selectedDeliveryOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseSelectDeliveryOption)),
      );
      return;
    }

    if (_selectedCondition == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.selectCondition)),
  );
  return;
}

    for (var color in _selectedColorImages.keys) {
      final hasExistingColorImage = isEditMode &&
          widget.existingProduct!.colorImages.containsKey(color) &&
          widget.existingProduct!.colorImages[color]!.isNotEmpty;

      if (_selectedColorImages[color]!['image'] == null &&
          !hasExistingColorImage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pleaseAddImageForColor)),
        );
        return;
      }
    }

    _showPreparingPreviewModal();
    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.pleaseLoginToContinue)),
          );
        }
        return;
      }

      // Fetch seller info (unchanged)
      Map<String, dynamic>? sellerInfo;
      if (_shopId != null) {
        final shopInfoSnap = await FirebaseFirestore.instance
            .collection('shops')
            .doc(_shopId)
            .collection('seller_info')
            .limit(1)
            .get();
        if (shopInfoSnap.docs.isNotEmpty) {
          sellerInfo =
              Map<String, dynamic>.from(shopInfoSnap.docs.first.data());
        }
      }

      if (sellerInfo == null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        sellerInfo =
            (userDoc.data() ?? {})['sellerInfo'] as Map<String, dynamic>?;
      }

      String? genderValue;
      final cleanedAttributes = Map<String, dynamic>.from(_attributes);

      if (cleanedAttributes.containsKey('gender')) {
        genderValue = cleanedAttributes['gender'] as String?;
        cleanedAttributes.remove('gender');
      }

      // ── Existing image URLs only — new images uploaded on confirm ──
      final List<String> existingImageUrls =
          isEditMode ? List<String>.from(_existingImageUrls) : [];

      // ── Color data: quantities for all colors, existing URLs only ──
      final colorQuantities = <String, int>{};
      final existingColorImageUrls = <String, List<String>>{};

      for (var entry in _selectedColorImages.entries) {
        final color = entry.key;
        final imageData = entry.value['image'];
        final quantity = entry.value['quantity'] as int?;

        if (quantity != null) {
          colorQuantities[color] = quantity;
        }

        // Carry over existing URLs; new XFile images uploaded on confirm
        if (imageData is String) {
          existingColorImageUrls[color] = [imageData];
        } else if (isEditMode &&
            widget.existingProduct!.colorImages.containsKey(color)) {
          existingColorImageUrls[color] =
              widget.existingProduct!.colorImages[color]!;
        }
      }

      // ── Existing video URL only — new video uploaded on confirm ──
      String? existingVideoUrl;
      if (isEditMode && widget.existingProduct?.videoUrl != null) {
        existingVideoUrl = widget.existingProduct!.videoUrl;
      }

      // Derive seller name
      String sellerName = user.displayName ?? 'Unknown User';
      if (_shopId != null) {
        final shopDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(_shopId)
            .get();
        if (shopDoc.exists) {
          sellerName = shopDoc.data()?['name'] ?? sellerName;
        }
      }

      List<String>? _getSpecList(String key) {
        final v = cleanedAttributes[key];
        return v is List ? List<String>.from(v) : null;
      }

      final specCleanedAttributes = Map<String, dynamic>.from(cleanedAttributes)
        ..remove('productType')
        ..remove('clothingSizes')
        ..remove('clothingFit')
        ..remove('clothingTypes')
        ..remove('pantSizes')
        ..remove('pantFabricTypes')
        ..remove('footwearSizes')
        ..remove('jewelryMaterials')
        ..remove('consoleBrand')
        ..remove('curtainMaxWidth')
        ..remove('curtainMaxHeight');

      // Build the Product with existing URLs — new uploads happen on confirm
      final product = Product(
        id: isEditMode ? widget.existingProduct!.id : '',
        ownerId: user.uid,
        productName: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        condition: _selectedCondition ?? '',
        brandModel: _selectedBrand ?? '',
        imageUrls: existingImageUrls,           // existing only
        averageRating: isEditMode ? widget.existingProduct!.averageRating : 0.0,
        reviewCount: isEditMode ? widget.existingProduct!.reviewCount : 0,
        gender: genderValue,
        boostClickCountAtStart:
            isEditMode ? widget.existingProduct!.boostClickCountAtStart : 0,
        userId: user.uid,
        shopId: _shopId,
        ilanNo: isEditMode ? widget.existingProduct!.ilanNo : '',
        currency: "TL",
        createdAt:
            isEditMode ? widget.existingProduct!.createdAt : Timestamp.now(),
        sellerName: sellerName,
        category: _selectedCategory ?? '',
        subcategory: _selectedSubcategory ?? '',
        subsubcategory: _selectedSubsubcategory ?? '',
        quantity: int.tryParse(_quantityController.text.trim()) ?? 1,
        colorQuantities: colorQuantities,
        colorImages: existingColorImageUrls,    // existing only
        deliveryOption: _selectedDeliveryOption ?? '',
        videoUrl: existingVideoUrl,             // existing only
        promotionScore: isEditMode ? widget.existingProduct!.promotionScore : 0,
        paused: isEditMode ? widget.existingProduct!.paused : false,
        isFeatured: isEditMode ? widget.existingProduct!.isFeatured : false,
        isBoosted: isEditMode ? widget.existingProduct!.isBoosted : false,
        boostedImpressionCount:
            isEditMode ? widget.existingProduct!.boostedImpressionCount : 0,
        boostImpressionCountAtStart: isEditMode
            ? widget.existingProduct!.boostImpressionCountAtStart
            : 0,
        clickCountAtStart:
            isEditMode ? widget.existingProduct!.clickCountAtStart : 0,
        productType: cleanedAttributes['productType'] as String?,
        clothingSizes: _getSpecList('clothingSizes'),
        clothingFit: cleanedAttributes['clothingFit'] as String?,
        clothingTypes: _getSpecList('clothingTypes'),
        pantSizes: _getSpecList('pantSizes'),
        pantFabricTypes: _getSpecList('pantFabricTypes'),
        footwearSizes: _getSpecList('footwearSizes'),
        jewelryMaterials: _getSpecList('jewelryMaterials'),
        consoleBrand: cleanedAttributes['consoleBrand'] as String?,
        curtainMaxWidth:
            (cleanedAttributes['curtainMaxWidth'] as num?)?.toDouble(),
        curtainMaxHeight:
            (cleanedAttributes['curtainMaxHeight'] as num?)?.toDouble(),
        attributes: _cleanAttributes(specCleanedAttributes),
      );

      if (mounted) {
        Navigator.of(context).pop();
        context.push('/list_product_preview', extra: {
          'product': product,
          'imageFiles': _imageFiles,                          // new images (not yet uploaded)
          'videoFile': _videoFiles.isNotEmpty ? _videoFiles.first : null, // new video
          'selectedColorImages': _selectedColorImages,        // raw color map with XFile images
          'phone': sellerInfo?['phone'] ?? '',
          'region': sellerInfo?['region'] ?? '',
          'address': sellerInfo?['address'] ?? '',
          'ibanOwnerName': sellerInfo?['ibanOwnerName'] ?? '',
          'ibanOwnerSurname': sellerInfo?['ibanOwnerSurname'] ?? '',
          'iban': sellerInfo?['iban'] ?? '',
          'isEditMode': isEditMode,
          'originalProduct': isEditMode ? widget.existingProduct : null,
          'isFromArchivedCollection': widget.isFromArchivedCollection,
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorListingProduct)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    String categoryDisplay = _selectedCategory != null &&
            _selectedSubcategory != null
        ? '${AllInOneCategoryData.localizeCategoryKey(_selectedCategory!, l10n)} > ${AllInOneCategoryData.localizeSubcategoryKey(_selectedCategory!, _selectedSubcategory!, l10n)}${_selectedSubsubcategory != null ? ' > ${AllInOneCategoryData.localizeSubSubcategoryKey(_selectedCategory!, _selectedSubcategory!, _selectedSubsubcategory!, l10n)}' : ''}'
        : l10n.category;

    final attributesDisplay = _formatAttributesDisplay();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditMode ? l10n.editProduct : l10n.listProduct,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        iconTheme:
            IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Container(
              color: isDarkMode
                  ? const Color(0xFF1C1A29)
                  : const Color(0xFFF5F5F5),
              child: SafeArea(
                bottom: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(0.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Text(
                            l10n.addVideoandImages,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
  child: Text(
    '${_imageFiles.length + _existingImageUrls.length}/10',
    style: TextStyle(
      fontSize: 12,
      color: (_imageFiles.length + _existingImageUrls.length) >= 10
          ? Colors.red
          : Colors.grey,
    ),
  ),
),
                         Stack(
  children: [
    Container(
      width: double.infinity,
      color: isDarkMode
          ? const Color.fromARGB(255, 33, 31, 49)
          : Colors.white,
      padding: const EdgeInsets.all(16.0),
      child: MediaPickerWidget(
        videoFile: _videoFiles.isNotEmpty
            ? _videoFiles.first
            : null,
        imageFiles: _imageFiles,
        existingImageUrls: _existingImageUrls,
        onPickVideo: _pickVideo,
        onRemoveVideo: () {
          if (_videoFiles.isNotEmpty) _removeVideo(0);
        },
        onPickImages: _pickImages,
        onRemoveImage: (index) {
          if (_imageFiles.isNotEmpty) _removeImage(index);
        },
        onRemoveExistingImage: (url) {
          setState(() {
            _existingImageUrls.remove(url);
          });
        },
      ),
    ),
    if (_isCompressing)
      Positioned.fill(
        child: Container(
          color: (isDarkMode
                  ? const Color.fromARGB(255, 33, 31, 49)
                  : Colors.white)
              .withOpacity(0.92),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFF00A86B),
                strokeWidth: 2.5,
              ),
              const SizedBox(height: 12),
              Text(
                'Compressing $_compressingCurrent of $_compressingTotal...',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _compressingTotal > 0
                      ? _compressingCurrent / _compressingTotal
                      : 0,
                  backgroundColor: isDarkMode
                      ? Colors.white12
                      : Colors.grey.shade200,
                  color: const Color(0xFF00A86B),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
  ],
),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Text(
                            l10n.productTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ProductInfoForm(
                          titleController: _titleController,
                          descriptionController: _descriptionController,
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Text(
                            l10n.details,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        // Category Selection
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _showCategoryPicker,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color.fromARGB(255, 33, 31, 49)
                                  : Colors.white,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    categoryDisplay,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _selectedCategory != null &&
                                              _selectedSubcategory != null
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Brand Selection (if set)
                        if (_selectedBrand != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _editBrand,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color.fromARGB(255, 33, 31, 49)
                                    : Colors.white,
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${l10n.brand}: $_selectedBrand',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: isDarkMode
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_selectedBrand != null) const SizedBox(height: 8),

                        // Color Selection (if any)
                        if (_selectedColorImages.isNotEmpty)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _editColors,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color.fromARGB(255, 33, 31, 49)
                                    : Colors.white,
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${l10n.color}: ${_formatColorDisplay()}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: isDarkMode
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_selectedColorImages.isNotEmpty)
                          const SizedBox(height: 8),

                        // Dynamic Attributes Display (individually clickable)
                        if (_attributes.isNotEmpty)
                          ..._attributes.entries.map((entry) {
                            final attributeKey = entry.key;
                            final attributeValue = entry.value;

                            final title = AttributeLocalizationUtils
                                .getLocalizedAttributeTitle(attributeKey, l10n);
                            final displayValue = AttributeLocalizationUtils
                                .getLocalizedAttributeValue(
                                    attributeKey, attributeValue, l10n);

                            final hasEditScreen =
                                AttributeRouteMapper.hasEditScreen(
                                    attributeKey);

                            return Column(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: hasEditScreen
                                      ? () => _editAttribute(attributeKey)
                                      : null,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? const Color.fromARGB(
                                              255, 33, 31, 49)
                                          : Colors.white,
                                      borderRadius: BorderRadius.zero,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '$title: $displayValue',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                          if (hasEditScreen)
                                            Icon(
                                              Icons.edit,
                                              size: 18,
                                              color: isDarkMode
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          }).toList(),

                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Text(
                            l10n.productCondition,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color.fromARGB(255, 33, 31, 49)
                                : Colors.white,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                _buildConditionRadio(
                                    l10n.brandNew, 'Brand New'),
                                const SizedBox(width: 16),
                                _buildConditionRadio(l10n.used, 'Used'),
                                const SizedBox(width: 16),
                                _buildConditionRadio(
                                    l10n.refurbished, 'Refurbished'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DeliveryOptionsAccordion(
                          selectedDeliveryOption: _selectedDeliveryOption,
                          onDeliveryOptionChanged: (value) {
                            setState(() {
                              _selectedDeliveryOption = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_shopId != null) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              l10n.quantity,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color.fromARGB(255, 33, 31, 49)
                                  : Colors.white,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: TextFormField(
                                controller: _quantityController,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: l10n.quantity,
                                ),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontSize: 14,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: false,
                                  signed: false,
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return l10n.pleaseEnterQuantity;
                                  }
                                  if (int.tryParse(value) == null ||
                                      int.parse(value) <= 0) {
                                    return l10n.pleaseEnterValidQuantity;
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Text(
                            l10n.price,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color.fromARGB(255, 33, 31, 49)
                                : Colors.white,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextFormField(
                              controller: _priceController,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: l10n.enterPrice,
                              ),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: false,
                              ),
                              inputFormatters: [
                                _PriceInputFormatter(),
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.pleaseEnterPrice;
                                }
                                if (double.tryParse(value) == null) {
                                  return l10n.pleaseEnterValidNumber;
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _navigateToPreview,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A86B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24.0),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 16.0,
                                ),
                              ),
                              child: Text(
                                isEditMode
                                    ? l10n.editProduct
                                    : l10n.continueButton,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                        ),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }

  Widget _buildConditionRadio(String label, String value) {
    return Row(
      children: [
        Radio<String>(
          value: value,
          groupValue: _selectedCondition,
          onChanged: (newValue) {
            setState(() {
              _selectedCondition = newValue;
            });
          },
          activeColor: const Color(0xFF00A86B),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}
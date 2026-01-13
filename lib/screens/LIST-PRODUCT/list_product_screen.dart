import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
import '../../utils/image_compression_utils.dart';
import '../../utils/attribute_route_mapper.dart';

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
      // Keep only the first dot
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

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
  bool _hasDefect = false;

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
      if (!mounted) return; // Add this safety check
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

      // Check all steps for matching conditions
      for (final step in flow.steps.values) {
        for (final nextStep in step.nextSteps) {
          final conditions = nextStep.conditions;
          if (conditions == null) continue;

          // Check category match
          final categoryList = conditions['category'];
          final categoryMatch =
              categoryList != null && categoryList.contains(cat);

          if (!categoryMatch) {
            continue;
          }

          // Check subcategory match
          final subcategoryList = conditions['subcategory'];
          bool subcategoryMatch = true;
          if (subcategoryList != null && subcategoryList.isNotEmpty) {
            subcategoryMatch = subcategoryList.contains(sub);
            if (!subcategoryMatch) {
              continue;
            }
          }

          // Check subsubcategory match
          final subSubcategoryList = conditions['subsubcategory'];
          bool subSubcategoryMatch = true;
          if (subSubcategoryList != null && subSubcategoryList.isNotEmpty) {
            subSubcategoryMatch = subSubcategoryList.contains(subsub);
            if (!subSubcategoryMatch) {
              continue;
            }
          }

          // Calculate specificity score
          // Higher score = more specific flow
          int specificity = 0;

          if (categoryList.isNotEmpty) specificity += 1;
          if (subcategoryList != null && subcategoryList.isNotEmpty)
            specificity += 10;
          if (subSubcategoryList != null && subSubcategoryList.isNotEmpty)
            specificity += 100;

          matchingFlows.add(MapEntry(flow, specificity));
          break; // Found a match for this flow, no need to check other steps
        }
      }
    }

    if (matchingFlows.isEmpty) {
      return null;
    }

    // Sort by specificity (highest first) and take the most specific
    matchingFlows.sort((a, b) => b.value.compareTo(a.value));

    final selectedFlow = matchingFlows.first;

    return selectedFlow.key;
  }

  /// Follow `nextSteps[0]` pointers to build an ordered list of stepIds.
  List<String> _linearizeFlow(ProductListingFlow flow) {
    final List<String> out = [];
    String? cur = flow.startStepId;
    final visited = <String>{};

    while (cur != null && !visited.contains(cur)) {
      // Prevent infinite loops
      visited.add(cur);
      out.add(cur);

      // Stop if we reach preview
      if (cur == 'preview') break;

      // Check if step exists
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
      // Pre-populate form fields
      _titleController.text = product.productName;
      _priceController.text = product.price.toString();
      _quantityController.text = product.quantity.toString();
      _descriptionController.text = product.description;

      // Pre-populate fixed selections
      _selectedCategory = product.category;
      _selectedSubcategory = product.subcategory;
      _selectedSubsubcategory = product.subsubcategory;
      _selectedBrand = product.brandModel;
      _selectedCondition = product.condition;
      _selectedDeliveryOption = product.deliveryOption;

      // Pre-populate existing images & colors
      _existingImageUrls = product.imageUrls;
      _selectedColorImages.clear();
      product.colorQuantities.forEach((color, qty) {
        _selectedColorImages[color] = {
          'quantity': qty,
          'image': null,
        };
      });

      // ✅ FIX: Load attributes and handle gender properly
      _attributes.clear();
      final cleanedAttrs = _cleanAttributes(product.attributes);
      _attributes.addAll(cleanedAttrs);

      // ✅ FIX: Check root-level gender first (from Web), then fallback to attributes (from Flutter)
      if (product.gender != null && product.gender!.isNotEmpty) {
        // Product has root-level gender (listed from Web)
        _attributes['gender'] = product.gender!;
      } else if (!_attributes.containsKey('gender') &&
          product.attributes.containsKey('gender')) {
        // Fallback: check if gender is in attributes (listed from Flutter)
        _attributes['gender'] = product.attributes['gender'];
      }
    });
  }

// Helper method to clean attributes
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

// Helper to validate attribute values
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

    return true; // For numbers, booleans, etc.
  }

  Future<void> _initializeWithImageAndCategory() async {
    if (widget.imageFile != null && widget.category != null) {
      setState(() {
        _selectedCategory = widget.category;
        _imageFiles.add(XFile(widget.imageFile!.path));
      });
    }
  }

  // FIX 1: Properly dismiss modal and refresh UI after image picker
  Future<void> _pickImages(ImageSource source) async {
    // Dismiss keyboard before showing image picker
    FocusScope.of(context).unfocus();

    // Add a small delay to ensure keyboard is fully dismissed
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      if (source == ImageSource.gallery) {
        final pickedFiles = await ImagePicker().pickMultiImage();
        if (pickedFiles.isNotEmpty) {
          // Use mounted check before setState
          if (mounted) {
            setState(() {
              _imageFiles.addAll(pickedFiles);
            });
          }
        }
      } else {
        // source == ImageSource.camera
        final pickedFile =
            await ImagePicker().pickImage(source: ImageSource.camera);
        if (pickedFile != null) {
          if (mounted) {
            setState(() {
              _imageFiles.add(pickedFile);
            });
          }
        }
      }
    } catch (e) {
      print('Error picking images: $e');
    }

    // Force rebuild to remove any UI artifacts
    if (mounted) {
      setState(() {});
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  // FIX 1: Properly dismiss modal and refresh UI after video picker
  Future<void> _pickVideo(ImageSource source) async {
    // Dismiss keyboard before showing video picker
    FocusScope.of(context).unfocus();

    // Add a small delay to ensure keyboard is fully dismissed
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      if (source == ImageSource.gallery) {
        final pickedFile =
            await ImagePicker().pickVideo(source: ImageSource.gallery);
        if (pickedFile != null) {
          if (mounted) {
            setState(() {
              _videoFiles = [pickedFile];
              _newVideoFile = pickedFile;
            });
          }
        }
      } else {
        // source == ImageSource.camera
        final pickedFile =
            await ImagePicker().pickVideo(source: ImageSource.camera);
        if (pickedFile != null) {
          if (mounted) {
            setState(() {
              _videoFiles = [pickedFile];
              _newVideoFile = pickedFile;
            });
          }
        }
      }
    } catch (e) {
      print('Error picking video: $e');
    }

    // Force rebuild to remove any UI artifacts
    if (mounted) {
      setState(() {});
    }
  }

  void _removeVideo(int index) {
    setState(() {
      _videoFiles.clear();
      _newVideoFile = null;
    });
  }

  // FIX 2: Properly dismiss keyboard before category picker
  Future<void> _showCategoryPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();

    // 1) pick category → category/sub/subsub
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

    // 2) if anything changed, clear dependent fields
    final changed = newCat != _selectedCategory ||
        newSub != _selectedSubcategory ||
        newSubSub != _selectedSubsubcategory;
    if (changed) {
      setState(() {
        _selectedBrand = null;
        _selectedColorImages = {};
        _attributes.clear(); // Clear all dynamic attributes
      });
    }

    // 3) update the basic fields
    setState(() {
      _selectedCategory = newCat;
      _selectedSubcategory = newSub;
      _selectedSubsubcategory = newSubSub;
    });

    // FIX: Ensure keyboard is FULLY dismissed before starting flow
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 200));

    // 4) find matching flow and execute it
    await _executeProductFlow(newCat, newSub, newSubSub);
  }

  Future<void> _executeProductFlow(
      String cat, String sub, String subsub) async {
    // Find matching flow from Firestore
    final flow = _findMatchingFlow(cat, sub, subsub);
    if (flow == null) return; // No matching flow found

    // Get linearized steps
    final stepIds = _linearizeFlow(flow);

    // Execute each step in sequence
    for (final stepId in stepIds) {
      final success = await _executeFlowStep(stepId, cat, sub, subsub);
      if (!success) {
        // User cancelled or error occurred, stop the flow
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

      // ALL other steps handled dynamically
      return await _executeDynamicStep(stepId, cat, sub, subsub);
    } catch (e) {
      return false;
    }
  }

// FIX 2: Ensure keyboard is dismissed before each dynamic step
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

      // Process result based on what it contains
      setState(() {
        if (result is Map<String, dynamic>) {
          // ✅ Check if empty map first (user wants to clear colors)
          if (result.isEmpty) {
            // Check if this was meant for colors by checking the route
            if (stepId == 'list_color') {
              _selectedColorImages.clear();
            }
            return; // Exit setState early
          }

          // Check if this is color data by examining the structure
          bool isColorData = false;

          // Check if all values in the map are maps containing 'image' and 'quantity' keys
          if (result.isNotEmpty) {
            isColorData = result.values.every((value) =>
                value is Map &&
                value.containsKey('image') &&
                value.containsKey('quantity'));
          }

          if (isColorData) {
            // This is color data from list_color screen

            _selectedColorImages.clear();
            result.forEach((key, value) {
              if (value is Map) {
                _selectedColorImages[key] = Map<String, dynamic>.from(value);
              }
            });
          } else {
            // This is regular attribute data
            // Handle top-level fields
            if (result.containsKey('brand')) {
              _selectedBrand = result['brand'] as String?;
            }

            // Everything else goes to attributes
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

  // Helper method to display dynamic attributes
  String _formatAttributesDisplay() {
    final l10n = AppLocalizations.of(context);
    return AttributeLocalizationUtils.formatAttributesDisplay(
        _attributes, l10n);
  }

  /// Navigates to brand selection screen to edit brand
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
        // Update other attributes if returned
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

    // Prepare initial color data for the screen with both images and quantities
    final Map<String, Map<String, dynamic>>? initialColorData;
    if (_selectedColorImages.isNotEmpty) {
      initialColorData =
          Map<String, Map<String, dynamic>>.from(_selectedColorImages);
    } else {
      initialColorData = null;
    }

    // ✅ Pass existing color image URLs from the original product
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
    // ✅ FIX: Handle empty map result (user wants to clear colors)
    if (result == null) return; // User cancelled, no changes

    setState(() {
      // ✅ FIX: Check for Map (any type), not just Map<String, dynamic>
      if (result is Map) {
        // ✅ If empty map, clear all colors
        if (result.isEmpty) {
          _selectedColorImages.clear();
          return;
        }

        // Check if this is color data
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

  /// Navigates to specific attribute screen to edit that attribute
  Future<void> _editAttribute(String attributeKey) async {
    if (_selectedCategory == null ||
        _selectedSubcategory == null ||
        _selectedSubsubcategory == null) {
      return;
    }

    final route = AttributeRouteMapper.getRouteForAttribute(attributeKey);
    if (route == null) return; // No screen available for this attribute

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
        // Update all returned attributes
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
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 8,
                  width: double.infinity,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(seconds: 2),
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00A86B),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToPreview() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
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

    for (var color in _selectedColorImages.keys) {
      // In edit mode, check if there are existing color images
      final hasExistingColorImage = isEditMode &&
          widget.existingProduct!.colorImages.containsKey(color) &&
          widget.existingProduct!.colorImages[color]!.isNotEmpty;

      // Check if there's a new image OR existing image
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

      // 1) Try to load the shop's own seller_info if we're in seller-panel mode
      Map<String, dynamic>? sellerInfo;
      if (_shopId != null) {
        final shopInfoSnap = await _firestore
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

      // 2) Fallback to the user's sellerInfo if no shop info found
      if (sellerInfo == null) {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        sellerInfo =
            (userDoc.data() ?? {})['sellerInfo'] as Map<String, dynamic>?;
      }

      String? genderValue;
      final cleanedAttributes = Map<String, dynamic>.from(_attributes);

      // Extract gender if it exists
      if (cleanedAttributes.containsKey('gender')) {
        genderValue = cleanedAttributes['gender'] as String?;
        cleanedAttributes.remove('gender');
      }

      List<String> defaultImageUrls = [];

      // Keep existing images in edit mode
      if (isEditMode) {
        defaultImageUrls.addAll(_existingImageUrls);
      }

      // Upload any new images
      if (_imageFiles.isNotEmpty) {
        final newImageUrls = await _uploadFiles(
          _imageFiles.map((x) => File(x.path)).toList(),
          'default_images',
        );
        defaultImageUrls.addAll(newImageUrls);
      }

      // ✅ FIXED: Handle color images properly
      final colorImagesUrls = <String, List<String>>{};
      final colorQuantities = <String, int>{};

      for (var entry in _selectedColorImages.entries) {
        final color = entry.key;
        final imageData = entry.value['image']; // ✅ Don't cast to XFile yet!
        final quantity = entry.value['quantity'] as int?;

        // ✅ Start fresh for this color (don't carry over old data)
        List<String>? urlsForThisColor;

        // ✅ Handle the image based on its actual type
        if (imageData != null) {
          if (imageData is XFile) {
            // ✅ New image uploaded - upload it
            final urls = await _uploadFiles(
              [File(imageData.path)],
              'color_images/$color',
            );
            urlsForThisColor = urls;
          } else if (imageData is String) {
            // ✅ Existing image URL kept - use it directly
            urlsForThisColor = [imageData];
          }
        } else if (isEditMode &&
            widget.existingProduct!.colorImages.containsKey(color)) {
          // ✅ No new image, but has existing image - keep existing
          urlsForThisColor = widget.existingProduct!.colorImages[color]!;
        }

        // ✅ Only add if we have valid URLs
        if (urlsForThisColor != null && urlsForThisColor.isNotEmpty) {
          colorImagesUrls[color] = urlsForThisColor;
        }

        if (quantity != null) {
          colorQuantities[color] = quantity;
        }
      }

      // Handle video - keep existing or upload new
      String? videoUrl;
      if (isEditMode && widget.existingProduct!.videoUrl != null) {
        videoUrl = widget.existingProduct!.videoUrl;
      }

      // Upload new video if provided (this will override existing)
      if (_videoFiles.isNotEmpty) {
        final tempVideoUrls = await _uploadFiles(
          _videoFiles.map((x) => File(x.path)).toList(),
          'preview_videos',
        );
        if (tempVideoUrls.isNotEmpty) {
          videoUrl = tempVideoUrls.first;
        }
      }

      // Derive sellerName (shop name overrides personal name)
      String sellerName = user.displayName ?? 'Unknown User';
      if (_shopId != null) {
        final shopDoc = await _firestore.collection('shops').doc(_shopId).get();
        if (shopDoc.exists) {
          sellerName = shopDoc.data()?['name'] ?? sellerName;
        }
      }

      // Build the Product model
      final product = Product(
        id: isEditMode ? widget.existingProduct!.id : '',
        ownerId: user.uid,
        productName: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        condition: _selectedCondition ?? '',
        brandModel: _selectedBrand ?? '',
        imageUrls:
            defaultImageUrls, // ✅ FIXED: Use combined URLs, not just existing
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
        colorImages: colorImagesUrls,
        deliveryOption: _selectedDeliveryOption ?? '',
        videoUrl: videoUrl,
        rankingScore: isEditMode ? widget.existingProduct!.rankingScore : 0,
        promotionScore: isEditMode ? widget.existingProduct!.promotionScore : 0,
        paused: isEditMode ? widget.existingProduct!.paused : false,
        isFeatured: isEditMode ? widget.existingProduct!.isFeatured : false,
        isTrending: isEditMode ? widget.existingProduct!.isTrending : false,
        isBoosted: isEditMode ? widget.existingProduct!.isBoosted : false,
        boostedImpressionCount:
            isEditMode ? widget.existingProduct!.boostedImpressionCount : 0,
        boostImpressionCountAtStart: isEditMode
            ? widget.existingProduct!.boostImpressionCountAtStart
            : 0,
        clickCountAtStart:
            isEditMode ? widget.existingProduct!.clickCountAtStart : 0,
        attributes:
            _cleanAttributes(cleanedAttributes), // ✅ Use cleaned attributes
      );

      if (mounted) {
        Navigator.of(context).pop();
        context.push('/list_product_preview', extra: {
          'product': product,
          'imageFiles': _imageFiles,
          'videoFile': _videoFiles.isNotEmpty ? _videoFiles.first : null,
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

  Future<List<String>> _uploadFiles(List<File> files, String folder) async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final userId = user.uid;

    try {
      final List<Future<String>> futures = [];

      for (final file in files) {
        futures.add(_compressAndUpload(file, userId, folder));
      }

      return await Future.wait(futures);
    } catch (e) {
      if (e.toString().contains('too large')) {
        // Show user-friendly error with localization
        final l10n = AppLocalizations.of(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.imageTooLarge), // or whatever key you add
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      rethrow;
    }
  }

  Future<String> _compressAndUpload(
      File file, String userId, String folder) async {
    try {
      // Check file size first
      final fileSize = await file.length();
      if (fileSize > 20 * 1024 * 1024) {
        // 20MB limit
        throw Exception('IMAGE_TOO_LARGE');
      }

      // Use e-commerce optimized compression
      final compressedFile =
          await ImageCompressionUtils.ecommerceCompress(file);

      // Use compressed file or original if compression failed
      final fileToUpload = compressedFile ?? file;

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final ref =
          FirebaseStorage.instance.ref('products/$userId/$folder/$fileName');

      final taskSnap = await ref.putFile(fileToUpload);
      return await taskSnap.ref.getDownloadURL();
    } catch (e) {
      if (e.toString().contains('IMAGE_TOO_LARGE')) {
        throw Exception('Image is too large. Maximum size is 20MB.');
      }
      rethrow; // Don't fallback for other errors
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
                              // Remove existing image from the list
                              setState(() {
                                _existingImageUrls.remove(url);
                              });
                            },
                          ),
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
                          onTap:
                              _showCategoryPicker, // SOLUTION 1: Direct call, no conditional logic
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

                            // Get localized title and value
                            final title = AttributeLocalizationUtils
                                .getLocalizedAttributeTitle(attributeKey, l10n);
                            final displayValue = AttributeLocalizationUtils
                                .getLocalizedAttributeValue(
                                    attributeKey, attributeValue, l10n);

                            // Check if this attribute has an edit screen
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

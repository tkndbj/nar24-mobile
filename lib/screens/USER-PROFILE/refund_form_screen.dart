import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import 'dart:ui';
import 'package:shimmer/shimmer.dart';

class RefundFormScreen extends StatefulWidget {
  const RefundFormScreen({Key? key}) : super(key: key);

  @override
  State<RefundFormScreen> createState() => _RefundFormScreenState();
}

class _RefundFormScreenState extends State<RefundFormScreen> {
  final _receiptNoController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _showSuccessModal = false;
  String? _receiptNoError;
  String? _descriptionError;

  User? _user;
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    _user = FirebaseAuth.instance.currentUser;

    if (_user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/login');
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          _profileData = userDoc.data();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  bool _validateForm() {
    bool isValid = true;
    setState(() {
      _receiptNoError = null;
      _descriptionError = null;
    });

    final localization = AppLocalizations.of(context);

    if (_receiptNoController.text.trim().isEmpty) {
      setState(() {
        _receiptNoError = localization.receiptNoRequired;
      });
      isValid = false;
    }

    if (_descriptionController.text.trim().isEmpty) {
      setState(() {
        _descriptionError = localization.descriptionRequired;
      });
      isValid = false;
    } else if (_descriptionController.text.trim().length < 20) {
      setState(() {
        _descriptionError = localization.descriptionTooShort;
      });
      isValid = false;
    }

    return isValid;
  }

  Future<void> _handleSubmit() async {
    if (_user == null || !_validateForm()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.collection('refund-forms').add({
        'userId': _user!.uid,
        'displayName': _profileData?['displayName'] ?? '',
        'email': _profileData?['email'] ?? _user!.email ?? '',
        'receiptNo': _receiptNoController.text.trim(),
        'description': _descriptionController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _showSuccessModal = true;
        _isSubmitting = false;
      });

      // Reset form and navigate back after delay
      await Future.delayed(const Duration(milliseconds: 2500));

      if (mounted) {
        setState(() {
          _receiptNoController.clear();
          _descriptionController.clear();
          _showSuccessModal = false;
        });
        context.pop();
      }
    } catch (error) {
      print('Error submitting refund request: $error');
      final localization = AppLocalizations.of(context);

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localization.submitError),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _receiptNoController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: _buildFormShimmer(isDarkMode),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: theme.scaffoldBackgroundColor,
              elevation: 0,
              leading: IconButton(
                icon: Icon(
                  FeatherIcons.arrowLeft,
                  color: theme.textTheme.bodyMedium?.color,
                ),
                onPressed: () => context.pop(),
              ),
              title: Text(
                localization.refundFormTitle,
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              centerTitle: true,
            ),
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Header Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.orange.withOpacity(0.1),
                            Colors.pink.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color.fromARGB(255, 33, 31, 49)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(40),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.shadowColor.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              FeatherIcons.fileText,
                              color: Colors.orange,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            localization.refundFormHeaderTitle,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            localization.refundFormHeaderSubtitle,
                            style: TextStyle(
                              fontSize: 15,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Form Fields - narrower and centered on tablet
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isTablet = constraints.maxWidth >= 600;
                        final formWidth = isTablet ? constraints.maxWidth * 0.65 : constraints.maxWidth;

                        return Center(
                          child: SizedBox(
                            width: formWidth,
                            child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Name Field
                          _buildFormCard(
                            icon: FeatherIcons.user,
                            label: localization.refundFormNameLabel,
                            child: TextFormField(
                              enabled: false,
                              initialValue: _profileData?['displayName'] ??
                                  localization.refundFormNoName,
                              style: TextStyle(
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(0.6),
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDarkMode
                                    ? const Color.fromARGB(255, 54, 50, 75)
                                    : Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                              ),
                            ),
                            theme: theme,
                            isDarkMode: isDarkMode,
                          ),

                          const SizedBox(height: 16),

                          // Email Field
                          _buildFormCard(
                            icon: FeatherIcons.mail,
                            label: localization.refundFormEmailLabel,
                            child: TextFormField(
                              enabled: false,
                              initialValue:
                                  _profileData?['email'] ?? _user?.email ?? '',
                              style: TextStyle(
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(0.6),
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDarkMode
                                    ? const Color.fromARGB(255, 54, 50, 75)
                                    : Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                              ),
                            ),
                            theme: theme,
                            isDarkMode: isDarkMode,
                          ),

                          const SizedBox(height: 16),

                          // Receipt Number Field
                         _buildFormCard(
  icon: FeatherIcons.fileText,
  label: localization.refundFormReceiptNoLabel,
  trailing: InkWell(
    onTap: () async {
      final result = await context.push('/refund-order-selection');
      
      if (result != null && result is Map<String, dynamic>) {
        final orderId = result['orderId'] as String?;
        final orderData = result['orderData'] as Map<String, dynamic>?;
        
        if (orderId != null && orderData != null) {
          setState(() {
            _receiptNoController.text = orderId;
            // Optionally store orderData for submission
            // You can add this data to the refund form submission
          });
        }
      }
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          localization.refundFormSelectOrder,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(
          FeatherIcons.externalLink,
          color: Colors.orange,
          size: 14,
        ),
      ],
    ),
  ),
  child: TextFormField(
    controller: _receiptNoController,
    readOnly: true, // Make it read-only since we're selecting from a list
    style: TextStyle(
      color: theme.textTheme.bodyMedium?.color,
      fontSize: 15,
    ),
    decoration: InputDecoration(
      hintText: localization.refundFormReceiptNoPlaceholder,
      hintStyle: TextStyle(
        color: theme.textTheme.bodyMedium?.color
            ?.withOpacity(0.5),
      ),
      filled: true,
      fillColor: isDarkMode
          ? const Color.fromARGB(255, 54, 50, 75)
          : Colors.grey[100], // Changed to grey to indicate read-only
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _receiptNoError != null
              ? Colors.red
              : isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.grey[300]!,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _receiptNoError != null
              ? Colors.red
              : isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.grey[300]!,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Colors.orange,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Colors.red,
        ),
      ),
      suffixIcon: _receiptNoController.text.isNotEmpty
          ? IconButton(
              icon: Icon(
                FeatherIcons.x,
                size: 18,
                color: theme.textTheme.bodyMedium?.color
                    ?.withOpacity(0.6),
              ),
              onPressed: () {
                setState(() {
                  _receiptNoController.clear();
                  _receiptNoError = null;
                });
              },
            )
          : null,
    ),
    onTap: () async {
      // Also allow tapping the field itself to open selection
      final result = await context.push('/refund-order-selection');
      
      if (result != null && result is Map<String, dynamic>) {
        final orderId = result['orderId'] as String?;
        final orderData = result['orderData'] as Map<String, dynamic>?;
        
        if (orderId != null && orderData != null) {
          setState(() {
            _receiptNoController.text = orderId;
          });
        }
      }
    },
  ),
  error: _receiptNoError,
  theme: theme,
  isDarkMode: isDarkMode,
),

                          const SizedBox(height: 16),

                          // Description Field
                          _buildFormCard(
                            icon: FeatherIcons.messageSquare,
                            label: localization.refundFormDescriptionLabel,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _descriptionController,
                                  maxLines: 6,
                                  style: TextStyle(
                                    color: theme.textTheme.bodyMedium?.color,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: localization
                                        .refundFormDescriptionPlaceholder,
                                    hintStyle: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.5),
                                    ),
                                    filled: true,
                                    fillColor: isDarkMode
                                        ? const Color.fromARGB(255, 54, 50, 75)
                                        : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _descriptionError != null
                                            ? Colors.red
                                            : isDarkMode
                                                ? Colors.white.withOpacity(0.1)
                                                : Colors.grey[300]!,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _descriptionError != null
                                            ? Colors.red
                                            : isDarkMode
                                                ? Colors.white.withOpacity(0.1)
                                                : Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Colors.orange,
                                        width: 2,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (_descriptionError != null) {
                                      setState(() => _descriptionError = null);
                                    }
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _descriptionError ??
                                            localization
                                                .refundFormDescriptionHelper,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _descriptionError != null
                                              ? Colors.red
                                              : theme
                                                  .textTheme.bodyMedium?.color
                                                  ?.withOpacity(0.6),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${_descriptionController.text.length}/20',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _descriptionController
                                                    .text.length >
                                                20
                                            ? Colors.red
                                            : theme.textTheme.bodyMedium?.color
                                                ?.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            theme: theme,
                            isDarkMode: isDarkMode,
                          ),

                          const SizedBox(height: 24),

                          // Submit Button
                          Container(
                            width: double.infinity,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: _isSubmitting
                                  ? null
                                  : const LinearGradient(
                                      colors: [Colors.orange, Colors.pink],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              color: _isSubmitting ? Colors.grey : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _isSubmitting ? null : _handleSubmit,
                                child: Center(
                                  child: _isSubmitting
                                      ? Shimmer.fromColors(
                                          baseColor: Colors.white.withOpacity(0.5),
                                          highlightColor: Colors.white,
                                          period: const Duration(milliseconds: 1200),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                FeatherIcons.send,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                localization.refundFormSubmitting,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              FeatherIcons.send,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              localization
                                                  .refundFormSubmitButton,
                                              style: const TextStyle(
                                                color: Colors.white,
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

                          const SizedBox(height: 24),

                          // Info Section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.blue.withOpacity(0.3)
                                    : Colors.blue[200]!,
                              ),
                            ),
                            child: Text(
                              localization.refundFormInfoMessage,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDarkMode
                                    ? Colors.blue[300]
                                    : Colors.blue[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),

          // Success Modal
          if (_showSuccessModal)
            Positioned.fill(
              child: Material(
                color: Colors.black.withOpacity(0.5),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(40),
                      constraints: const BoxConstraints(maxWidth: 400),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Success Icon
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.green, Color(0xFF4CAF50)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Title
                          Text(
                            localization.refundFormSuccessTitle,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),

                          // Description
                          Text(
                            localization.refundFormSubmitSuccess,
                            style: TextStyle(
                              fontSize: 15,
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black54,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),

                          // Processing Time Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  FeatherIcons.clock,
                                  color: Colors.green,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
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

  Widget _buildFormShimmer(bool isDarkMode) {
    return SafeArea(
      child: Shimmer.fromColors(
        baseColor: isDarkMode
            ? const Color(0xFF1E1C2C)
            : const Color(0xFFE0E0E0),
        highlightColor: isDarkMode
            ? const Color(0xFF211F31)
            : const Color(0xFFF5F5F5),
        period: const Duration(milliseconds: 1200),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header shimmer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 200,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 250,
                      height: 15,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Form fields shimmer
              ...List.generate(
                4,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 100,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          height: index == 3 ? 120 : 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Submit button shimmer
              Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard({
    required IconData icon,
    required String label,
    required Widget child,
    Widget? trailing,
    String? error,
    required ThemeData theme,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            isDarkMode ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

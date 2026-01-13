import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SupportAndFaqScreen extends StatefulWidget {
  const SupportAndFaqScreen({Key? key}) : super(key: key);

  @override
  State<SupportAndFaqScreen> createState() => _SupportAndFaqScreenState();
}

class _SupportAndFaqScreenState extends State<SupportAndFaqScreen> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    void _showSuccessModal(
        BuildContext context, AppLocalizations localization, bool isDarkMode) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          });

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  Text(
                    localization.successTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localization.submitSuccess,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    void _showHelpFormModal(
        BuildContext context, AppLocalizations localization, bool isDarkMode) {
      final descriptionController = TextEditingController();
      final currentUser = FirebaseAuth.instance.currentUser;
      String? descriptionError;
      bool isSubmitting = false;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              final screenWidth = MediaQuery.of(context).size.width;
              final screenHeight = MediaQuery.of(context).size.height;
              final isTablet = screenWidth >= 600;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  // Tablet: use constraints with max height, Mobile: fixed 75% height
                  height: isTablet ? null : screenHeight * 0.75,
                  constraints: isTablet
                      ? BoxConstraints(maxHeight: screenHeight * 0.6)
                      : null,
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color.fromARGB(255, 33, 31, 49)
                        : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: isTablet ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.pink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 40),
                            Text(
                              localization.helpFormTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(FeatherIcons.x,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),

                      // Form Content - Flexible on tablet, Expanded on mobile
                      if (isTablet)
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              // Name Field
                              Text(
                                localization.nameLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                enabled: false,
                                initialValue: currentUser?.displayName ??
                                    localization.noName,
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Email Field
                              Text(
                                localization.emailLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                enabled: false,
                                initialValue: currentUser?.email ?? '',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Description Field
                              Text(
                                localization.descriptionLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: descriptionController,
                                maxLines: 4, // Reduced lines for tablet
                                style: TextStyle(
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                                decoration: InputDecoration(
                                  hintText: localization.descriptionPlaceholder,
                                  hintStyle: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: descriptionError != null
                                          ? Colors.red
                                          : (isDarkMode
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: descriptionError != null
                                          ? Colors.red
                                          : (isDarkMode
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.orange,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  setModalState(() {
                                    if (descriptionError != null) {
                                      descriptionError = null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      descriptionError ??
                                          localization.descriptionHelper,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: descriptionError != null
                                            ? Colors.red
                                            : (isDarkMode
                                                ? Colors.white60
                                                : Colors.black54),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${descriptionController.text.length}/20',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          descriptionController.text.length < 20
                                              ? Colors.red
                                              : (isDarkMode
                                                  ? Colors.white60
                                                  : Colors.black54),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Submit Button
                              Container(
                                width: double.infinity,
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: isSubmitting
                                      ? null
                                      : const LinearGradient(
                                          colors: [Colors.orange, Colors.pink],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                  color: isSubmitting ? Colors.grey : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: isSubmitting
                                        ? null
                                        : () async {
                                            // Validate
                                            if (descriptionController.text
                                                .trim()
                                                .isEmpty) {
                                              setModalState(() {
                                                descriptionError = localization
                                                    .descriptionRequired;
                                              });
                                              return;
                                            }

                                            if (descriptionController.text
                                                    .trim()
                                                    .length <
                                                20) {
                                              setModalState(() {
                                                descriptionError = localization
                                                    .descriptionTooShort;
                                              });
                                              return;
                                            }

                                            setModalState(() {
                                              isSubmitting = true;
                                            });

                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('help-forms')
                                                  .add({
                                                'userId':
                                                    currentUser?.uid ?? '',
                                                'displayName':
                                                    currentUser?.displayName ??
                                                        '',
                                                'email':
                                                    currentUser?.email ?? '',
                                                'description':
                                                    descriptionController.text
                                                        .trim(),
                                                'status': 'pending',
                                                'createdAt': FieldValue
                                                    .serverTimestamp(),
                                              });

                                              Navigator.pop(context);
                                              _showSuccessModal(context,
                                                  localization, isDarkMode);
                                            } catch (error) {
                                              print(
                                                  'Error submitting help form: $error');
                                              setModalState(() {
                                                isSubmitting = false;
                                              });
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      localization.submitError),
                                                  backgroundColor: Colors.red,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          },
                                    child: Center(
                                      child: isSubmitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  FeatherIcons.mail,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  localization.submitButton,
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
                            ],
                          ),
                        ),
                      )
                      else
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Name Field
                              Text(
                                localization.nameLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                enabled: false,
                                initialValue: currentUser?.displayName ??
                                    localization.noName,
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Email Field
                              Text(
                                localization.emailLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                enabled: false,
                                initialValue: currentUser?.email ?? '',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Description Field
                              Text(
                                localization.descriptionLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: descriptionController,
                                maxLines: 6,
                                style: TextStyle(
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                                decoration: InputDecoration(
                                  hintText: localization.descriptionPlaceholder,
                                  hintStyle: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: descriptionError != null
                                          ? Colors.red
                                          : (isDarkMode
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: descriptionError != null
                                          ? Colors.red
                                          : (isDarkMode
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.orange,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  setModalState(() {
                                    if (descriptionError != null) {
                                      descriptionError = null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      descriptionError ??
                                          localization.descriptionHelper,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: descriptionError != null
                                            ? Colors.red
                                            : (isDarkMode
                                                ? Colors.white60
                                                : Colors.black54),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${descriptionController.text.length}/20',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          descriptionController.text.length < 20
                                              ? Colors.red
                                              : (isDarkMode
                                                  ? Colors.white60
                                                  : Colors.black54),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Submit Button
                              Container(
                                width: double.infinity,
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: isSubmitting
                                      ? null
                                      : const LinearGradient(
                                          colors: [Colors.orange, Colors.pink],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                  color: isSubmitting ? Colors.grey : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: isSubmitting
                                        ? null
                                        : () async {
                                            // Validate
                                            if (descriptionController.text
                                                .trim()
                                                .isEmpty) {
                                              setModalState(() {
                                                descriptionError = localization
                                                    .descriptionRequired;
                                              });
                                              return;
                                            }

                                            if (descriptionController.text
                                                    .trim()
                                                    .length <
                                                20) {
                                              setModalState(() {
                                                descriptionError = localization
                                                    .descriptionTooShort;
                                              });
                                              return;
                                            }

                                            setModalState(() {
                                              isSubmitting = true;
                                            });

                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('help-forms')
                                                  .add({
                                                'userId':
                                                    currentUser?.uid ?? '',
                                                'displayName':
                                                    currentUser?.displayName ??
                                                        '',
                                                'email':
                                                    currentUser?.email ?? '',
                                                'description':
                                                    descriptionController.text
                                                        .trim(),
                                                'status': 'pending',
                                                'createdAt': FieldValue
                                                    .serverTimestamp(),
                                              });

                                              Navigator.pop(context);
                                              _showSuccessModal(context,
                                                  localization, isDarkMode);
                                            } catch (error) {
                                              print(
                                                  'Error submitting help form: $error');
                                              setModalState(() {
                                                isSubmitting = false;
                                              });
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      localization.submitError),
                                                  backgroundColor: Colors.red,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          },
                                    child: Center(
                                      child: isSubmitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  FeatherIcons.mail,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  localization.submitButton,
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
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // FAQ Data - using localized strings
    final List<Map<String, String>> faqData = [
      {
        'question': localization.faqShippingQuestion,
        'answer': localization.faqShippingAnswer,
      },
      {
        'question': localization.faqReturnQuestion,
        'answer': localization.faqReturnAnswer,
      },
      {
        'question': localization.faqPaymentQuestion,
        'answer': localization.faqPaymentAnswer,
      },
      {
        'question': localization.faqAccountQuestion,
        'answer': localization.faqAccountAnswer,
      },
      {
        'question': localization.faqOrderQuestion,
        'answer': localization.faqOrderAnswer,
      },
      {
        'question': localization.faqRefundQuestion,
        'answer': localization.faqRefundAnswer,
      },
      {
        'question': localization.faqSellerQuestion,
        'answer': localization.faqSellerAnswer,
      },
      {
        'question': localization.faqSafetyQuestion,
        'answer': localization.faqSafetyAnswer,
      },
    ];

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
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
            localization.supportAndFaq,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Header Section with Image and Title
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
                ),
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(60),
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(60),
                        child: Image.asset(
                          'assets/images/support.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      localization.supportTitle,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localization.supportSubtitle,
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // FAQ Section Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.pink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        FeatherIcons.helpCircle,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      localization.frequentlyAskedQuestions,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // FAQ List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: faqData.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final faq = faqData[index];
                    final isExpanded = _expandedIndex == index;

                    return Container(
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Color.fromARGB(255, 33, 31, 49)
                            : theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExpanded
                              ? Colors.orange.withOpacity(0.3)
                              : Colors.transparent,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              _expandedIndex = isExpanded ? null : index;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        faq['question']!,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              theme.textTheme.bodyMedium?.color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AnimatedRotation(
                                      turns: isExpanded ? 0.5 : 0,
                                      duration:
                                          const Duration(milliseconds: 200),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: isExpanded
                                              ? Colors.orange.withOpacity(0.1)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          FeatherIcons.chevronDown,
                                          color: isExpanded
                                              ? Colors.orange
                                              : theme
                                                  .textTheme.bodyMedium?.color
                                                  ?.withOpacity(0.6),
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  height: isExpanded ? null : 0,
                                  child: isExpanded
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 12),
                                            Container(
                                              height: 1,
                                              color:
                                                  Colors.grey.withOpacity(0.2),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              faq['answer']!,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: theme
                                                    .textTheme.bodyMedium?.color
                                                    ?.withOpacity(0.8),
                                                height: 1.5,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 32),

              // Still Need Help Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Color.fromARGB(255, 33, 31, 49)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.orange.withOpacity(0.2)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Icon(
                          FeatherIcons.mail,
                          color: Colors.orange,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        localization.stillNeedHelp,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        localization.stillNeedHelpDescription,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color
                              ?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.pink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showHelpFormModal(
                                  context, localization, isDarkMode);
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  FeatherIcons.mail,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.contactSupport,
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

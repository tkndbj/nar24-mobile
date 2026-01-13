// lib/screens/complete_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../user_provider.dart';
import '../../providers/profile_provider.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({Key? key}) : super(key: key);

  @override
  _CompleteProfileScreenState createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? _selectedGender;
  DateTime? _selectedBirthDate;
  bool _isLoading = false;
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();

    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeOut,
    ));

    _fadeInController.forward();
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    super.dispose();
  }

  // format DateTime as DD/MM/YYYY
  String get _birthDateText {
    if (_selectedBirthDate == null) return '';
    final d = _selectedBirthDate!;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial =
        _selectedBirthDate ?? DateTime(now.year - 18, now.month, now.day);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? const ColorScheme.dark(
                  primary: Colors.orange,
                  onPrimary: Colors.white,
                  surface: Color.fromARGB(255, 37, 35, 54),
                  onSurface: Colors.white,
                )
              : const ColorScheme.light(
                  primary: Colors.orange,
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
          textButtonTheme: isDark
              ? TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                )
              : null, dialogTheme: DialogThemeData(backgroundColor: isDark
              ? const Color.fromARGB(255, 37, 35, 54)
              : null),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedBirthDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final user = FirebaseAuth.instance.currentUser;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeInAnimation,
            child: Column(
              children: [
                // Top bar with back/skip buttons
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new,
                            color: isDark ? Colors.white70 : Colors.black54,
                            size: 18,
                          ),
                          onPressed: () {
                            // Go back or to home - don't sign out
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            } else {
                              context.go('/');
                            }
                          },
                        ),
                      ),
                      // Skip button
                      TextButton(
                        onPressed: () {
                          // Navigate to home without completing profile
                          context.go('/');
                        },
                        child: Text(
                          l10n.skip ?? 'Skip',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: screenHeight * 0.02),

                          // Header
                          _buildHeader(l10n, isDark, user),

                          SizedBox(height: screenHeight * 0.03),

                          // Form fields
                          _buildFormFields(l10n, isDark),

                          const SizedBox(height: 24),

                          // Save button
                          _buildSaveButton(l10n, isDark),

                          const SizedBox(height: 16),

                          // Info text
                          _buildInfoBox(l10n, isDark),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isDark, User? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.orange, Color(0xFFFF4081)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.person_add_alt_1_outlined,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(height: 20),

        // Title
        Text(
          l10n.completeProfile,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),

        // User email
        if (user?.email != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.email_outlined,
                  size: 14,
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
                const SizedBox(width: 6),
                Text(
                  user!.email!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontFamily: 'Figtree',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),

        // Subtitle
        Text(
          l10n.pleaseFillMissingFields,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildFormFields(AppLocalizations l10n, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gender dropdown
        _buildInputLabel(l10n.selectGender, isDark),
        const SizedBox(height: 6),
        _buildGenderDropdown(l10n, isDark),
        const SizedBox(height: 14),

        // Birth date
        _buildInputLabel(l10n.selectBirthDate, isDark),
        const SizedBox(height: 6),
        _buildBirthDateField(l10n, isDark),
      ],
    );
  }

  Widget _buildInputLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }

  Widget _buildGenderDropdown(AppLocalizations l10n, bool isDark) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      isExpanded: true,
      dropdownColor:
          isDark ? const Color.fromARGB(255, 45, 42, 62) : Colors.white,
      style: TextStyle(
        fontFamily: 'Figtree',
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: l10n.selectGender,
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontFamily: 'Figtree',
        ),
        prefixIcon: Icon(
          Icons.people_outline,
          color: isDark ? Colors.white38 : Colors.black38,
          size: 20,
        ),
        filled: true,
        fillColor:
            isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.orange.shade400,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      items: [
        DropdownMenuItem(value: 'Male', child: Text(l10n.male)),
        DropdownMenuItem(value: 'Female', child: Text(l10n.female)),
        DropdownMenuItem(value: 'Other', child: Text(l10n.other)),
      ],
      onChanged: (v) => setState(() => _selectedGender = v),
      validator: (v) =>
          v == null ? l10n.requiredField(l10n.selectGender) : null,
    );
  }

  Widget _buildBirthDateField(AppLocalizations l10n, bool isDark) {
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: _birthDateText),
      style: TextStyle(
        fontFamily: 'Figtree',
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: l10n.selectBirthDate,
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontFamily: 'Figtree',
        ),
        prefixIcon: Icon(
          Icons.calendar_today_outlined,
          color: isDark ? Colors.white38 : Colors.black38,
          size: 20,
        ),
        suffixIcon: Icon(
          Icons.edit_calendar,
          color: isDark ? Colors.white38 : Colors.black38,
          size: 20,
        ),
        filled: true,
        fillColor:
            isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.orange.shade400,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      onTap: _pickBirthDate,
      validator: (_) => _selectedBirthDate == null
          ? l10n.requiredField(l10n.selectBirthDate)
          : null,
    );
  }

  Widget _buildSaveButton(AppLocalizations l10n, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        onPressed: _isLoading ? null : _submit,
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                l10n.save,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                ),
              ),
      ),
    );
  }

  Widget _buildInfoBox(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: isDark ? Colors.white38 : Colors.black38,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.profileCompletionInfo ??
                  'Complete your profile to access all features',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45,
                fontFamily: 'Figtree',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No signed-in user found.');

      // Verify user has valid auth token
      try {
        await user.getIdToken();
      } catch (e) {
        throw Exception('Authentication expired. Please login again.');
      }

      // Get the device language code for Firestore rules requirement
      final languageCode = Localizations.localeOf(context).languageCode;

      final data = {
        'gender': _selectedGender,
        'birthDate': _selectedBirthDate,
        'languageCode': languageCode, // Required by Firestore rules
        'isNew': false, // mark profile complete
        'agreementsAccepted': true,
        'agreementAcceptedAt': FieldValue.serverTimestamp(),
      };

      // ✅ CRITICAL FIX: Use set with merge instead of update
      // This ensures the operation succeeds even if document creation was delayed
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      // Retry logic for robustness under heavy load
      const maxRetries = 3;
      int retryCount = 0;
      bool success = false;

      while (retryCount < maxRetries && !success) {
        try {
          await docRef.set(data, SetOptions(merge: true));
          success = true;
        } catch (e) {
          retryCount++;
          debugPrint('⚠️ Profile update attempt $retryCount failed: $e');
          if (retryCount < maxRetries) {
            await Future.delayed(
                Duration(milliseconds: 250 * (1 << retryCount)));
          } else {
            rethrow;
          }
        }
      }

      // Refresh both UserProvider and ProfileProvider to ensure UI updates
      await Future.wait([
        Provider.of<UserProvider>(context, listen: false).refreshUser(),
        Provider.of<ProfileProvider>(context, listen: false).refreshUser(),
      ]);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                    l10n.profileCompleted ?? 'Profile completed successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

      // only navigate if this widget is still mounted:
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(e.toString())),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      // if we've already navigated away, `mounted` will be false and we won't call setState
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

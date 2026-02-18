import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../user_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

class CapitalizeFirstLetterFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    // Capitalize first letter of each word
    final words = newValue.text.split(' ');
    final capitalized = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    return TextEditingValue(
      text: capitalized,
      selection: newValue.selection,
    );
  }
}

class CompleteNameScreen extends StatefulWidget {
  final String userId;

  const CompleteNameScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<CompleteNameScreen> createState() => _CompleteNameScreenState();
}

class _CompleteNameScreenState extends State<CompleteNameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  bool _isLoading = false;

  // Prevent duplicate saves
  bool _hasSaved = false;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    // Guard against duplicate saves
    if (_hasSaved || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _hasSaved = true;
    });

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // Step 1: Lock to prevent background fetches from overwriting
    userProvider.setNameSaveInProgress(true);

    try {
      final displayName =
          '${_nameController.text.trim()} ${_surnameController.text.trim()}';

      // Step 2: Update Firestore FIRST
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
        'displayName': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Step 3: Update Firebase Auth profile
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName);
      }

      // Step 4: Update UserProvider state (this controls router redirect)
      userProvider.setNameComplete(true);

      // Step 5: Update UserProvider's cached profile data directly
      // This ensures immediate consistency without waiting for Firestore fetch
      userProvider.updateLocalProfileField('displayName', displayName);

      // Step 6: Refresh UserProvider — ProfileProvider auto-syncs via its listener
      if (mounted) {
        try {
          await Provider.of<UserProvider>(context, listen: false).refreshUser();
        } catch (e) {
          debugPrint('UserProvider refresh: $e');
        }
      }

      // Step 7: Unlock BEFORE navigation
      userProvider.setNameSaveInProgress(false);

      // Step 8: Navigate - use go() to let router re-evaluate
      // This is cleaner than pop() as it works regardless of navigation stack
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      // Rollback on error
      userProvider.setNameSaveInProgress(false);
      userProvider.setNameComplete(false);
      _hasSaved = false;

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Icon
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        size: 40,
                        color: Colors.orange,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Title
                  Center(
                    child: Text(
                      l10n.whatsYourName ?? "What's your name?",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Center(
                    child: Text(
                      l10n.nameNeededForOrders ??
                          'We need your name for order delivery',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // First Name
                  Text(
                    l10n.firstName ?? 'First Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [CapitalizeFirstLetterFormatter()],
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: l10n.firstNameHint ?? 'Enter your first name',
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.orange.shade400, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.firstNameRequired ??
                            'First name is required';
                      }
                      if (value.trim().length < 2) {
                        return l10n.nameTooShort ?? 'Name is too short';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Last Name
                  Text(
                    l10n.lastName ?? 'Last Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _surnameController,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [CapitalizeFirstLetterFormatter()],
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: l10n.lastNameHint ?? 'Enter your last name',
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.orange.shade400, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.lastNameRequired ?? 'Last name is required';
                      }
                      if (value.trim().length < 2) {
                        return l10n.nameTooShort ?? 'Name is too short';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  // Continue button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveName,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              l10n.continueButton ?? 'Continue',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

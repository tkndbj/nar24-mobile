import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../generated/l10n/app_localizations.dart';
import '../screens/AGREEMENTS/registration_agreement_screen.dart';
import '../screens/AGREEMENTS/kullanim_kosullari.dart';
import '../screens/AGREEMENTS/kisisel_veriler.dart';

/// A modal dialog that requires users to accept agreements.
/// This is shown to Google-registered users who haven't accepted agreements yet.
class AgreementModal extends StatefulWidget {
  final VoidCallback onAccepted;

  const AgreementModal({
    Key? key,
    required this.onAccepted,
  }) : super(key: key);

  /// Local storage key for agreement acceptance (per user)
  static String _getAgreementKey(String uid) => 'agreements_accepted_$uid';

  /// Check if user has accepted agreements (from local storage)
  static Future<bool> hasAcceptedAgreements(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_getAgreementKey(uid)) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking agreement status: $e');
      return false;
    }
  }

  /// Clear agreement acceptance (call on logout)
  static Future<void> clearAgreementStatus(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getAgreementKey(uid));
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing agreement status: $e');
    }
  }

  /// Shows the agreement modal as a non-dismissible dialog.
  /// Returns true if agreements were accepted, false otherwise.
  static Future<bool> show(BuildContext context) async {
    bool accepted = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => AgreementModal(
        onAccepted: () {
          accepted = true;
          Navigator.of(context).pop();
        },
      ),
    );

    return accepted;
  }

  @override
  State<AgreementModal> createState() => _AgreementModalState();
}

class _AgreementModalState extends State<AgreementModal> {
  bool _isLoading = false;
  bool _isChecked = false;

  Future<void> _acceptAgreements() async {
    if (!_isChecked) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // User not authenticated - close modal and let them login
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      // Verify user can get a valid token before writing
      try {
        await user.getIdToken();
      } catch (e) {
        // Token invalid - user session expired, close modal
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      // CRITICAL: Save to SharedPreferences FIRST (this always works)
      // This ensures the modal won't appear again even if Firestore fails
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AgreementModal._getAgreementKey(user.uid), true);

      // Try to update Firestore as well (may fail due to security rules)
      // This is secondary - the local storage is the primary source
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'agreementsAccepted': true,
          'agreementAcceptedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Firestore write failed (likely due to security rules requiring profile fields)
        // This is OK - local storage has the acceptance recorded
        // It will sync to Firestore when user completes their profile
        if (kDebugMode) {
          debugPrint('Firestore agreement write failed (expected for incomplete profiles): $e');
        }
      }

      widget.onAccepted();
    } catch (e) {
      if (mounted) {
        // Check if it's an auth error - if so, close modal
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('permission') ||
            errorString.contains('unauthenticated') ||
            errorString.contains('unauthorized') ||
            errorString.contains('not authenticated')) {
          Navigator.of(context).pop();
          return;
        }

        // For other errors, show snackbar but allow retry
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).errorGeneral ??
                  'An error occurred. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevent back button dismissal
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: isDark
                ? const Color.fromARGB(255, 33, 31, 49)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.orange, Color(0xFFFF4081)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.handshake_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    l10n.agreementRequired ?? 'Agreement Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                      fontFamily: 'Figtree',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Description
                  Text(
                    l10n.agreementModalDescription ??
                        'To continue using the app, please review and accept our terms and agreements.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontFamily: 'Figtree',
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Agreement links container
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildAgreementLink(
                          icon: Icons.description_outlined,
                          title: l10n.membershipAgreement ?? 'Membership Agreement',
                          isDark: isDark,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const RegistrationAgreementScreen(),
                            ),
                          ),
                        ),
                        Divider(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                          height: 20,
                        ),
                        _buildAgreementLink(
                          icon: Icons.article_outlined,
                          title: l10n.termsOfUse ?? 'Terms of Use',
                          isDark: isDark,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const TermsOfUseScreen(),
                            ),
                          ),
                        ),
                        Divider(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                          height: 20,
                        ),
                        _buildAgreementLink(
                          icon: Icons.privacy_tip_outlined,
                          title: l10n.personalData ?? 'Personal Data',
                          isDark: isDark,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PersonalDataScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Checkbox
                  GestureDetector(
                    onTap: () => setState(() => _isChecked = !_isChecked),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isChecked
                            ? (isDark
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.orange.shade50)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isChecked
                              ? Colors.orange.shade400
                              : (isDark ? Colors.white24 : Colors.grey.shade300),
                          width: _isChecked ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _isChecked,
                              onChanged: (value) {
                                setState(() => _isChecked = value ?? false);
                              },
                              activeColor: Colors.orange,
                              checkColor: Colors.white,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(
                                color:
                                    isDark ? Colors.white38 : Colors.black38,
                                width: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.iHaveReadAndAccept ??
                                  'I have read and accept all agreements',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontFamily: 'Figtree',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Accept button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          _isChecked && !_isLoading ? _acceptAgreements : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.grey.shade200,
                        disabledForegroundColor: isDark
                            ? Colors.white38
                            : Colors.grey.shade500,
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
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              l10n.acceptAndContinue ?? 'Accept & Continue',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Figtree',
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

  Widget _buildAgreementLink({
    required IconData icon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.orange.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                  fontFamily: 'Figtree',
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

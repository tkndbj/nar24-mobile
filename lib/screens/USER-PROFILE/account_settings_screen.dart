import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../auth_service.dart';
import '../../services/two_factor_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _twoFactorEnabled = false;
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _smsNotifications = false;
  bool _isLoading = false;

  final TwoFactorService _twoFactorService = TwoFactorService();

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data();
          setState(() {
            _twoFactorEnabled = data?['twoFactorEnabled'] ?? false;
            _notificationsEnabled = data?['notificationsEnabled'] ?? true;
            _emailNotifications = data?['emailNotifications'] ?? true;
            _pushNotifications = data?['pushNotifications'] ?? true;
            _smsNotifications = data?['smsNotifications'] ?? false;
          });
        }
      }
    } catch (e) {
      print('Error loading user settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handle2FAToggle(bool value) async {
    final localization = AppLocalizations.of(context);

    if (value) {
      // Enable 2FA
      await _enable2FA();
    } else {
      // Disable 2FA
      await _disable2FA();
    }
  }

  Future<void> _enable2FA() async {
    final localization = AppLocalizations.of(context);

    try {
      // Show loading modal
      _show2FASetupModal();

      // Start TOTP-based 2FA setup (no phone number needed anymore)
      final result = await _twoFactorService.start2FASetup();

      if (mounted) {
        Navigator.of(context).pop(); // Close loading modal
      }

      if (result['success'] == true) {
        // Navigate to the verification screen (TOTP deep-link/QR/manual + 6-digit input)
        final verificationResult = await context.push<bool>(
          '/two_factor_verification',
          extra: {
            'type': 'setup',
            // NOTE: phoneNumber removed (TOTP flow does not need it)
          },
        );

        if (verificationResult == true) {
          // Reload settings to reflect the change
          await _loadUserSettings();
        }
      } else {
        _showErrorSnackBar(
          (result['message'] is String &&
                  (result['message'] as String).isNotEmpty)
              ? result['message']
              : localization.twoFactorSetupError,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading modal if still open
      }
      _showErrorSnackBar(localization.twoFactorSetupError);
    }
  }

  Future<void> _disable2FA() async {
    final localization = AppLocalizations.of(context);

    try {
      // Show loading modal
      _show2FADisableModal();

      // Start disable flow (TOTP preferred, email as fallback)
      final result = await _twoFactorService.start2FADisable();

      if (mounted) {
        Navigator.of(context).pop(); // Close loading modal
      }

      if (result['success'] == true) {
        // Navigate to the verification screen (enter TOTP code or email code)
        final verificationResult = await context.push<bool>(
          '/two_factor_verification',
          extra: {
            'type': 'disable',
            // NOTE: phoneNumber removed (not needed in TOTP or email fallback UI)
          },
        );

        if (verificationResult == true) {
          // Reload settings to reflect the change
          await _loadUserSettings();
        }
      } else {
        _showErrorSnackBar(
          (result['message'] is String &&
                  (result['message'] as String).isNotEmpty)
              ? result['message']
              : localization.twoFactorDisableError,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading modal if still open
      }
      _showErrorSnackBar(localization.twoFactorDisableError);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updateUserSetting(String field, bool value) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({field: value});
      }
    } catch (e) {
      print('Error updating setting: $e');
    }
  }

  // Cached callable region — single instance, reused across precheck / transfer / delete.
  static final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  // Orchestrates the full deletion flow:
  //   1. precheckAccountDeletion  (read-only, learns ownership state)
  //   2. transfer_required        → bottom sheet to transfer ownership, then re-precheck
  //   3. solo_owner_warning       → server-localized warning, then continue
  //   4. clear / accepted warning → email-confirm dialog, then deleteUserAccount
  //
  // Re-entrant via recursion after a successful transfer.
  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final localization = AppLocalizations.of(context);
    final userEmail = FirebaseAuth.instance.currentUser?.email;

    if (userEmail == null) {
      _showErrorSnackBar(localization.deleteAccountFailed);
      return;
    }

    // Step 1 — precheck (with loading modal).
    Map<String, dynamic>? precheck;
    _showPrecheckLoadingModal();
    try {
      precheck = await _precheckAccountDeletion();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorSnackBar(e.message ?? localization.deleteAccountFailed);
      return;
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      _showErrorSnackBar(localization.deleteAccountFailed);
      return;
    }
    if (mounted) Navigator.of(context).pop(); // close loading
    if (!mounted || precheck == null) return;

    final status = precheck['status'] as String? ?? 'clear';
    final messages = (precheck['messages'] as Map?)?.cast<String, dynamic>();

    // Step 2 — transfer required: surface entities + members, transfer one, re-run.
    if (status == 'transfer_required') {
      final transferRequired =
          ((precheck['transferRequired'] as List?) ?? const [])
              .cast<Map<dynamic, dynamic>>()
              .map((e) => e.cast<String, dynamic>())
              .toList();

      final didTransfer = await _showTransferOwnershipFlow(
        transferRequired,
        _pickServerMessage(messages),
      );

      if (didTransfer && mounted) {
        // Re-run from the top — the precheck may now show solo_owner_warning or clear.
        await _showDeleteAccountDialog(context);
      }
      return;
    }

    // Step 3 — solo owner warning: show server-localized confirmation.
    bool confirmDisableOwned = false;
    if (status == 'solo_owner_warning') {
      final accepted = await _showSoloOwnerWarning(_pickServerMessage(messages));
      if (!accepted || !mounted) return;
      confirmDisableOwned = true;
    }

    // Step 4 — final email-confirmation gate, then call delete.
    final confirmed = await _showDeleteConfirmation(userEmail);
    if (!confirmed || !mounted) return;

    await _callDeleteUserAccount(
      email: userEmail,
      confirmDisableOwned: confirmDisableOwned,
    );
  }

  // Calls `precheckAccountDeletion`. Returns the parsed payload, or null on
  // missing data. Throws FirebaseFunctionsException upward for the orchestrator
  // to surface.
  Future<Map<String, dynamic>?> _precheckAccountDeletion() async {
    final result = await _fns.httpsCallable('precheckAccountDeletion').call({});
    final data = result.data;
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  // Picks the localized message from the server payload using the active app
  // locale, falling back to English then to an empty string.
  String _pickServerMessage(Map<String, dynamic>? messages) {
    if (messages == null) return '';
    final code = Localizations.localeOf(context).languageCode;
    final msg = messages[code] ?? messages['en'] ?? '';
    return msg is String ? msg : '';
  }

  // Calls `deleteUserAccount`. Handles the full success path (logout + redirect)
  // and any error including a stale-precheck `failed-precondition` (the server
  // recheck saw a state change between our precheck and this call — re-runs the
  // flow so the user sees up-to-date guidance).
  Future<void> _callDeleteUserAccount({
    required String email,
    required bool confirmDisableOwned,
  }) async {
    final localization = AppLocalizations.of(context);

    _showDeletingAccountModal();

    try {
      await _fns.httpsCallable('deleteUserAccount').call({
        'email': email,
        if (confirmDisableOwned) 'confirmDisableOwned': true,
      });

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      await AuthService().logout();
      if (!mounted) return;
      context.go('/login');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      // If state changed between precheck and now (e.g., a co-owner just
      // accepted an invitation), re-run the orchestrator so the user sees
      // current guidance instead of a raw error.
      if (e.code == 'failed-precondition') {
        await _showDeleteAccountDialog(context);
        return;
      }
      _showErrorSnackBar(e.message ?? localization.deleteAccountFailed);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading
      _showErrorSnackBar(localization.deleteAccountFailed);
    }
  }

  // Lightweight "checking your account" loading modal shown during precheck.
  void _showPrecheckLoadingModal() {
    final localization = AppLocalizations.of(context);
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Text(
                localization.checkingYourAccount,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Server-localized warning shown when the user owns shop(s)/restaurant(s)
  // with no other members. Returns true if the user accepts disabling them.
  Future<bool> _showSoloOwnerWarning(String message) async {
    final localization = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.deepOrange],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        localization.deleteAccount,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.45,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          localization.no,
                          style: TextStyle(
                            color:
                                isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          localization.continueText,
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
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  // Bottom sheet that lists each owned-with-members entity and its members.
  // Tapping a member runs `transferOwnership` for that (entity, member) pair.
  // Returns true if at least one transfer succeeded so the orchestrator
  // re-runs the precheck.
  Future<bool> _showTransferOwnershipFlow(
    List<Map<String, dynamic>> transferRequired,
    String headerMessage,
  ) async {
    if (transferRequired.isEmpty) return false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white;

    bool didTransfer = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            FeatherIcons.userCheck,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).transferOwnershipTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (headerMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        headerMessage,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white70
                              : Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                  // Entity + member list
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: transferRequired.length,
                      itemBuilder: (_, index) {
                        final entity = transferRequired[index];
                        return _buildEntityMembersBlock(
                          entity: entity,
                          isDark: isDark,
                          onTransferred: () {
                            didTransfer = true;
                            Navigator.of(sheetContext).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return didTransfer;
  }

  Widget _buildEntityMembersBlock({
    required Map<String, dynamic> entity,
    required bool isDark,
    required VoidCallback onTransferred,
  }) {
    final entityId = entity['id'] as String? ?? '';
    final entityType = entity['type'] as String? ?? 'shop';
    final entityName = (entity['name'] as String?)?.trim().isNotEmpty == true
        ? entity['name'] as String
        : entityId;
    final members = ((entity['members'] as List?) ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();

    final typeIcon = entityType == 'restaurant'
        ? FeatherIcons.coffee
        : FeatherIcons.shoppingBag;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entity header
          Row(
            children: [
              Icon(typeIcon, size: 16, color: isDark ? Colors.white70 : Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entityName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...members.map((member) => _buildMemberTile(
                entityId: entityId,
                entityType: entityType,
                entityName: entityName,
                member: member,
                isDark: isDark,
                onTransferred: onTransferred,
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMemberTile({
    required String entityId,
    required String entityType,
    required String entityName,
    required Map<String, dynamic> member,
    required bool isDark,
    required VoidCallback onTransferred,
  }) {
    final memberUid = member['uid'] as String? ?? '';
    final role = member['role'] as String? ?? '';
    final displayName =
        (member['displayName'] as String?)?.trim().isNotEmpty == true
            ? member['displayName'] as String
            : memberUid;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.15),
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          role,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.grey.shade600,
          ),
        ),
        trailing: const Icon(
          FeatherIcons.chevronRight,
          size: 18,
        ),
        onTap: () => _handleMemberTransferTap(
          entityId: entityId,
          entityType: entityType,
          entityName: entityName,
          memberUid: memberUid,
          memberDisplayName: displayName,
          onTransferred: onTransferred,
        ),
      ),
    );
  }

  Future<void> _handleMemberTransferTap({
    required String entityId,
    required String entityType,
    required String entityName,
    required String memberUid,
    required String memberDisplayName,
    required VoidCallback onTransferred,
  }) async {
    final localization = AppLocalizations.of(context);

    final confirmed = await _showTransferConfirmation(
      entityName: entityName,
      memberDisplayName: memberDisplayName,
    );
    if (!confirmed || !mounted) return;

    // Loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );

    try {
      await _fns.httpsCallable('transferOwnership').call({
        'entityId': entityId,
        'entityType': entityType,
        'newOwnerId': memberUid,
      });

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localization.ownershipTransferredSuccess(
              entityName,
              memberDisplayName,
            ),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      onTransferred();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading
      _showErrorSnackBar(e.message ?? localization.deleteAccountFailed);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading
      _showErrorSnackBar(localization.deleteAccountFailed);
    }
  }

  Future<bool> _showTransferConfirmation({
    required String entityName,
    required String memberDisplayName,
  }) async {
    final localization = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          localization.transferOwnershipConfirmTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          localization.transferOwnershipConfirmMessage(
            memberDisplayName,
            entityName,
          ),
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              localization.no,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              localization.transferAction,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<bool> _showDeleteConfirmation(String userEmail) async {
    final localization = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        FeatherIcons.trash2,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        localization.deleteAccount,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              localization.deleteAccountWarning ??
                                  'This action cannot be undone. All your data will be permanently deleted.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        hintText: localization.enterEmailToConfirm,
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey,
                          fontSize: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          localization.no,
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          final input = ctrl.text.trim();
                          if (input != userEmail) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(localization.emailMismatch),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.of(context).pop(true);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(FeatherIcons.trash2, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              localization.delete ?? 'Delete',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  void _show2FASetupModal() {
    final localization = AppLocalizations.of(context);
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
                          colors: [Colors.orange, Colors.pink],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        FeatherIcons.key,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                localization.setting2FA,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localization.setting2FADesc,
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orange,
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

  void _show2FADisableModal() {
    final localization = AppLocalizations.of(context);
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
                          colors: [Colors.grey, Colors.blueGrey],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        FeatherIcons.key,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                localization.disabling2FA,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localization.disabling2FADesc,
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blueGrey,
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

  void _showDeletingAccountModal() {
    final localization = AppLocalizations.of(context);
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
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        FeatherIcons.trash2,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                localization.deletingAccount ?? 'Deleting account...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localization.deletingAccountDesc ??
                    'Please wait while we delete your account and all associated data.',
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
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.red),
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

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

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
            localization.accountSettings,
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
          child: _isLoading
              ? _buildSettingsShimmer(isDarkMode)
              : SingleChildScrollView(
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
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.pink],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Icon(
                              FeatherIcons.settings,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            localization.accountSettingsTitle,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            localization.accountSettingsSubtitle,
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Security Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                                  FeatherIcons.shield,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                localization.securitySettings,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Two-Factor Authentication
                          Container(
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Color.fromARGB(255, 33, 31, 49)
                                  : theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
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
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: _twoFactorEnabled
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.grey.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        FeatherIcons.key,
                                        color: _twoFactorEnabled
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            localization.twoFactorAuth,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: theme
                                                  .textTheme.bodyMedium?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            localization.twoFactorAuthDesc,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: theme
                                                  .textTheme.bodyMedium?.color
                                                  ?.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _twoFactorEnabled,
                                      onChanged: (value) async {
                                        await _handle2FAToggle(value);
                                      },
                                      activeThumbColor: Colors.green,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Notifications Section
                          Row(
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
                                  FeatherIcons.bell,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                localization.notificationSettings,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Notifications Container
                          Container(
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Color.fromARGB(255, 33, 31, 49)
                                  : theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.shadowColor.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Master Notifications Toggle
                                _buildNotificationTile(
                                  icon: FeatherIcons.bell,
                                  title: localization.allNotifications,
                                  subtitle: localization.allNotificationsDesc,
                                  value: _notificationsEnabled,
                                  onChanged: (value) {
                                    setState(() {
                                      _notificationsEnabled = value;
                                      if (!value) {
                                        _emailNotifications = false;
                                        _pushNotifications = false;
                                        _smsNotifications = false;
                                      }
                                    });
                                    _updateUserSetting(
                                        'notificationsEnabled', value);
                                  },
                                  theme: theme,
                                  showDivider: true,
                                ),

                                // Email Notifications
                                _buildNotificationTile(
                                  icon: FeatherIcons.mail,
                                  title: localization.emailNotifications,
                                  subtitle: localization.emailNotificationsDesc,
                                  value: _emailNotifications &&
                                      _notificationsEnabled,
                                  onChanged: _notificationsEnabled
                                      ? (value) {
                                          setState(() {
                                            _emailNotifications = value;
                                          });
                                          _updateUserSetting(
                                              'emailNotifications', value);
                                        }
                                      : null,
                                  theme: theme,
                                  showDivider: true,
                                ),

                                // Push Notifications
                                _buildNotificationTile(
                                  icon: FeatherIcons.smartphone,
                                  title: localization.pushNotifications,
                                  subtitle: localization.pushNotificationsDesc,
                                  value: _pushNotifications &&
                                      _notificationsEnabled,
                                  onChanged: _notificationsEnabled
                                      ? (value) {
                                          setState(() {
                                            _pushNotifications = value;
                                          });
                                          _updateUserSetting(
                                              'pushNotifications', value);
                                        }
                                      : null,
                                  theme: theme,
                                  showDivider: true,
                                ),

                                // SMS Notifications
                                _buildNotificationTile(
                                  icon: FeatherIcons.messageSquare,
                                  title: localization.smsNotifications,
                                  subtitle: localization.smsNotificationsDesc,
                                  value: _smsNotifications &&
                                      _notificationsEnabled,
                                  onChanged: _notificationsEnabled
                                      ? (value) {
                                          setState(() {
                                            _smsNotifications = value;
                                          });
                                          _updateUserSetting(
                                              'smsNotifications', value);
                                        }
                                      : null,
                                  theme: theme,
                                  showDivider: false,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Danger Zone Section
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  FeatherIcons.alertTriangle,
                                  color: Colors.red,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                localization.dangerZone,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Delete Account Button
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Color.fromARGB(255, 33, 31, 49)
                                  : theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
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
                                onTap: () => _showDeleteAccountDialog(context),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          FeatherIcons.trash2,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              localization.deleteAccount,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              localization.deleteAccountDesc,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: theme
                                                    .textTheme.bodyMedium?.color
                                                    ?.withOpacity(0.7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        FeatherIcons.chevronRight,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildSettingsShimmer(bool isDark) {
    final baseColor =
        isDark ? const Color(0xFF1E1C2C) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF211F31) : const Color(0xFFF5F5F5);

    Widget buildShimmerTile() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Icon placeholder
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 16),
              // Text placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Switch placeholder
              Container(
                width: 40,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSectionHeader() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 160,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        period: const Duration(milliseconds: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            // Security section header
            buildSectionHeader(),
            const SizedBox(height: 8),
            buildShimmerTile(),
            const SizedBox(height: 24),
            // Notifications section header
            buildSectionHeader(),
            const SizedBox(height: 8),
            buildShimmerTile(),
            buildShimmerTile(),
            buildShimmerTile(),
            buildShimmerTile(),
            const SizedBox(height: 24),
            // Danger zone header
            buildSectionHeader(),
            const SizedBox(height: 8),
            buildShimmerTile(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool)? onChanged,
    required ThemeData theme,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: value && onChanged != null
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color:
                      value && onChanged != null ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: onChanged != null
                            ? theme.textTheme.bodyMedium?.color
                            : theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.green,
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 1,
              color: Colors.grey.withOpacity(0.2),
            ),
          ),
      ],
    );
  }
}

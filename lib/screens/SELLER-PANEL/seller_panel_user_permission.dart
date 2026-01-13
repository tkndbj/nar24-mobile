import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';

class SellerPanelUserPermission extends StatefulWidget {
  final String shopId;

  const SellerPanelUserPermission({
    Key? key,
    required this.shopId,
  }) : super(key: key);

  @override
  State<SellerPanelUserPermission> createState() =>
      _SellerPanelUserPermissionState();
}

class _SellerPanelUserPermissionState extends State<SellerPanelUserPermission> {
  final _emailController = TextEditingController();
  String _selectedRole = 'viewer';
  final List<String> _roles = ['co-owner', 'editor', 'viewer'];
  bool _isSending = false;
  late final Future<void> _shopLoadFuture;

  // Safety timer to prevent stuck loading state
  Timer? _initSafetyTimer;
  bool _initTimedOut = false;
  static const Duration _maxInitDuration = Duration(seconds: 12);

  bool _isValidEmail(String email) {
    final emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegExp.hasMatch(email.trim());
  }

  @override
  void initState() {
    super.initState();
    _startInitSafetyTimer();
    _shopLoadFuture = _ensureShopSelected();
  }

  @override
  void dispose() {
    _initSafetyTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  /// Safety timer to prevent stuck on initial loading
  void _startInitSafetyTimer() {
    _initSafetyTimer = Timer(_maxInitDuration, () {
      if (mounted && !_initTimedOut) {
        debugPrint('⚠️ User permission init safety timer triggered');
        setState(() => _initTimedOut = true);
      }
    });
  }

  /// Cancel safety timer when init completes successfully
  void _cancelInitSafetyTimer() {
    _initSafetyTimer?.cancel();
  }

  Future<void> _ensureShopSelected() async {
    // Get provider reference before async gap
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final current = provider.selectedShop;
    if (current == null || current.id != widget.shopId) {
      await provider.switchShop(widget.shopId);
    }
    _cancelInitSafetyTimer();
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _sendInvitation(SellerPanelProvider provider) async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty || provider.selectedShop == null) return;
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidEmail)),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (!mounted) return;

      if (userQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.userNotFound)),
        );
        setState(() => _isSending = false);
        return;
      }

      await provider.sendShopInvitation(email, _selectedRole);

      if (!mounted) return;

      setState(() => _isSending = false);
      _showSuccessSnackbar(l10n.invitationSentSuccessfully);
      _emailController.clear();
    } catch (e) {
      debugPrint('Firestore error: $e');
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorSendingInvitation(e.toString()))),
      );
    }
  }

  Future<void> _cancelInvitation(String invitationId) async {
    final l10n = AppLocalizations.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('shopInvitations')
          .doc(invitationId)
          .delete();

      if (!mounted) return;
      _showSuccessSnackbar(l10n.invitationCancelled);
    } catch (e) {
      debugPrint('Error cancelling invitation: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorCancellingInvitation(e.toString()))),
      );
    }
  }

  Future<void> _revokeAccess(
      String userId, String role, String userName) async {
    final l10n = AppLocalizations.of(context);

    // Show confirmation first
    final confirmed = await _showRevokeConfirmation(userName, role);
    if (!confirmed || !mounted) return;

    // Track modal state to prevent double-closing
    bool modalClosed = false;

    // Helper function to safely close the modal
    void closeModal() {
      if (modalClosed) return;
      modalClosed = true;

      // Try multiple approaches to ensure modal is closed
      if (mounted) {
        // First try: Use the root navigator
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // Show loading modal
    _showRevokingAccessModal(userName);

    // Safety timer to prevent modal from getting stuck
    final safetyTimer = Timer(const Duration(seconds: 15), () {
      if (!modalClosed && mounted) {
        debugPrint('⚠️ Revoke access safety timer triggered - forcing modal close');
        closeModal();
      }
    });

    try {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      final result = await provider.revokeUserAccess(userId, role);

      // Cancel the safety timer since operation completed
      safetyTimer.cancel();

      // Close modal first, then show result
      closeModal();

      // Wait a frame to ensure modal is closed before showing snackbar
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) return;

      // Check the result message to determine success or failure
      final isSuccess = result.toLowerCase().contains('success') ||
          result.toLowerCase().contains('revoked');

      if (isSuccess) {
        _showSuccessSnackbar(l10n.accessRevokedSuccessfully);
      } else {
        // Provider returned an error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(result)),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      // Cancel the safety timer
      safetyTimer.cancel();

      // Close modal first
      closeModal();

      // Wait a frame to ensure modal is closed
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.errorRevokingAccess(e.toString())),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<bool> _showRevokeConfirmation(String userName, String role) async {
    final l10n = AppLocalizations.of(context);
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
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.person_remove_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.revokeAccess ?? 'Revoke Access',
                        style: GoogleFonts.figtree(
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
                child: Container(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: GoogleFonts.figtree(
                                fontSize: 14,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.revokeAccessConfirmation ??
                                  'This will remove their access to the shop.',
                              style: GoogleFonts.figtree(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          l10n.cancel,
                          style: GoogleFonts.figtree(
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
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_remove_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              l10n.revoke ?? 'Revoke',
                              style: GoogleFonts.figtree(
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

  void _showRevokingAccessModal(String userName) {
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
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.person_remove_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                l10n.revokingAccess ?? 'Revoking access...',
                style: GoogleFonts.figtree(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                userName,
                style: GoogleFonts.figtree(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

  String getLocalizedRole(String role, AppLocalizations l10n) {
    switch (role) {
      case 'co-owner':
        return l10n.roleCoOwner;
      case 'editor':
        return l10n.roleEditor;
      case 'viewer':
        return l10n.roleViewer;
      case 'owner':
        return l10n.roleOwner;
      default:
        return role;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner':
        return const Color(0xFFFF6200);
      case 'co-owner':
        return const Color(0xFF00A86B);
      case 'editor':
        return const Color(0xFF2196F3);
      case 'viewer':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.admin_panel_settings;
      case 'co-owner':
        return Icons.supervisor_account;
      case 'editor':
        return Icons.edit;
      case 'viewer':
        return Icons.visibility;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<void>(
      future: _shopLoadFuture,
      builder: (context, snapshot) {
        // Show shimmer during initial load (unless safety timer triggered)
        if (snapshot.connectionState == ConnectionState.waiting && !_initTimedOut) {
          return Scaffold(
            backgroundColor: isDarkMode
                ? const Color(0xFF1C1A29)
                : const Color(0xFFF8F9FA),
            appBar: AppBar(
              title: Text(
                l10n.userPermissions,
                style: GoogleFonts.figtree(
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDarkMode
                  ? const Color.fromARGB(255, 33, 31, 49)
                  : Colors.white,
              elevation: 0,
            ),
            body: _buildInitialLoadingShimmer(isDarkMode),
          );
        }
        if (snapshot.hasError || _initTimedOut) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                l10n.userPermissions,
                style: GoogleFonts.figtree(
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDarkMode ? null : Colors.white,
              elevation: 0,
              shadowColor: Colors.black.withValues(alpha: 0.1),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _initTimedOut
                        ? l10n.initializationFailed
                        : '${l10n.initializationFailed}: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.figtree(
                      color: isDarkMode ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Consumer<SellerPanelProvider>(
          builder: (context, provider, child) {
            final shopData =
                provider.selectedShop?.data() as Map<String, dynamic>?;
            final selectedShopName = shopData != null
                ? (shopData['name'] as String? ?? l10n.noShopSelected)
                : l10n.noShopSelected;
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            final bool canManageInvitations = currentUserId != null &&
                (shopData?['ownerId'] == currentUserId ||
                    (shopData?['coOwners'] as List<dynamic>?)
                            ?.contains(currentUserId) ==
                        true);

            return Scaffold(
              backgroundColor: isDarkMode
                  ? const Color(0xFF1C1A29)
                  : const Color(0xFFF8F9FA),
              appBar: AppBar(
                title: Text(
                  l10n.userPermissions,
                  style: GoogleFonts.figtree(
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                backgroundColor: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                elevation: 0,
                shadowColor: Colors.black.withOpacity(0.05),
                surfaceTintColor: Colors.transparent,
              ),
              body: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Shop Info Header ───────────────────────────
                      Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF6200),
                            const Color(0xFFFF6200).withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.store,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  selectedShopName,
                                  style: GoogleFonts.figtree(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.managingPermissionsFor(selectedShopName),
                            style: GoogleFonts.figtree(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Invite Form Section ────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDarkMode ? 0.3 : 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF00A86B).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.person_add,
                                  color: const Color(0xFF00A86B),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l10n.sendInvitation,
                                style: GoogleFonts.figtree(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: l10n.emailInvitee,
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0xFF00A86B),
                                  width: 2,
                                ),
                              ),
                              filled: true,
                              fillColor: isDarkMode
                                  ? Colors.grey.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRole,
                            decoration: InputDecoration(
                              labelText: l10n.role,
                              prefixIcon: Icon(Icons.security),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0xFF00A86B),
                                  width: 2,
                                ),
                              ),
                              filled: true,
                              fillColor: isDarkMode
                                  ? Colors.grey.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            items: _roles.map((role) {
                              return DropdownMenuItem<String>(
                                value: role,
                                child: Row(
                                  children: [
                                    Icon(
                                      _getRoleIcon(role),
                                      color: _getRoleColor(role),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(getLocalizedRole(role, l10n)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedRole = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _isSending
                                  ? null
                                  : () => _sendInvitation(provider),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A86B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 1,
                              ),
                              child: _isSending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.send, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          l10n.sendInvitation,
                                          style: GoogleFonts.figtree(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Accepted Users Section ────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDarkMode ? 0.3 : 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF00A86B).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.group,
                                  color: const Color(0xFF00A86B),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l10n.acceptedUsers,
                                style: GoogleFonts.figtree(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('shops')
                                .doc(widget.shopId)
                                .snapshots(),
                            builder: (context, shopSnap) {
                              if (shopSnap.hasData && shopSnap.data!.exists) {
                                final shopData = shopSnap.data!.data()
                                    as Map<String, dynamic>;
                                final String ownerId =
                                    shopData['ownerId'] as String;
                                final List<String> coOwners =
                                    (shopData['coOwners'] as List<dynamic>?)
                                            ?.cast<String>() ??
                                        [];
                                final List<String> editors =
                                    (shopData['editors'] as List<dynamic>?)
                                            ?.cast<String>() ??
                                        [];
                                final List<String> viewers =
                                    (shopData['viewers'] as List<dynamic>?)
                                            ?.cast<String>() ??
                                        [];

                                final List<Map<String, String>> acceptedList =
                                    [];
                                acceptedList
                                    .add({'userId': ownerId, 'role': 'owner'});
                                for (var id in coOwners) {
                                  acceptedList
                                      .add({'userId': id, 'role': 'co-owner'});
                                }
                                for (var id in editors) {
                                  acceptedList
                                      .add({'userId': id, 'role': 'editor'});
                                }
                                for (var id in viewers) {
                                  acceptedList
                                      .add({'userId': id, 'role': 'viewer'});
                                }

                                if (acceptedList.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.group_outlined,
                                            size: 40,
                                            color: Colors.grey.withOpacity(0.5),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            l10n.noAcceptedUsers,
                                            style: GoogleFonts.figtree(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: acceptedList.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final entry = acceptedList[index];
                                    final userId = entry['userId']!;
                                    final role = entry['role']!;

                                    return FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(userId)
                                          .get(),
                                      builder: (context, userSnap) {
                                        String displayName = userId;
                                        if (userSnap.hasData &&
                                            userSnap.data!.exists) {
                                          final data = userSnap.data!.data()
                                              as Map<String, dynamic>;
                                          displayName = (data['displayName']
                                                  as String?) ??
                                              userId;
                                        }

                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 6),
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: _getRoleColor(role)
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  displayName.isNotEmpty
                                                      ? displayName[0]
                                                          .toUpperCase()
                                                      : '?',
                                                  style: GoogleFonts.figtree(
                                                    fontWeight: FontWeight.bold,
                                                    color: _getRoleColor(role),
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            title: Text(
                                              displayName,
                                              style: GoogleFonts.figtree(
                                                fontWeight: FontWeight.w600,
                                                color: isDarkMode
                                                    ? Colors.white
                                                    : Colors.black,
                                                fontSize: 14,
                                              ),
                                            ),
                                            subtitle: Row(
                                              children: [
                                                Icon(
                                                  _getRoleIcon(role),
                                                  size: 12,
                                                  color: _getRoleColor(role),
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  getLocalizedRole(role, l10n),
                                                  style: GoogleFonts.figtree(
                                                    color: _getRoleColor(role),
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (role == 'owner') ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFFF6200),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Text(
                                                      'OWNER',
                                                      style:
                                                          GoogleFonts.figtree(
                                                        fontSize: 9,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            trailing: canManageInvitations &&
                                                    role != 'owner'
                                                ? Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.red
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(
                                                          Icons.person_remove,
                                                          color: Colors.red,
                                                          size: 18),
                                                      onPressed: () =>
                                                          _revokeAccess(
                                                              userId,
                                                              role,
                                                              displayName),
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              }
                              return _buildAcceptedShimmer(isDarkMode);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Pending Invitations Section ───────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDarkMode ? 0.3 : 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.schedule,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l10n.pendingInvitations,
                                style: GoogleFonts.figtree(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('shopInvitations')
                                .where('shopId', isEqualTo: widget.shopId)
                                .where('status', isEqualTo: 'pending')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final docs = snapshot.data!.docs;
                                if (docs.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.inbox_outlined,
                                            size: 40,
                                            color: Colors.grey.withOpacity(0.5),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            l10n.noPendingInvitations,
                                            style: GoogleFonts.figtree(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: docs.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final doc = docs[index];
                                    final docData =
                                        doc.data() as Map<String, dynamic>;
                                    final inviteEmail =
                                        docData['email'] as String? ??
                                            'Unknown';
                                    final role =
                                        docData['role'] as String? ?? 'unknown';
                                    final invitationId = doc.id;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: _getRoleColor(role)
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Center(
                                            child: Text(
                                              inviteEmail[0].toUpperCase(),
                                              style: GoogleFonts.figtree(
                                                fontWeight: FontWeight.bold,
                                                color: _getRoleColor(role),
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          inviteEmail,
                                          style: GoogleFonts.figtree(
                                            fontWeight: FontWeight.w600,
                                            color: isDarkMode
                                                ? Colors.white
                                                : Colors.black,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: Row(
                                          children: [
                                            Icon(
                                              _getRoleIcon(role),
                                              size: 12,
                                              color: _getRoleColor(role),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              getLocalizedRole(role, l10n),
                                              style: GoogleFonts.figtree(
                                                color: _getRoleColor(role),
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: canManageInvitations
                                            ? Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.red
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: IconButton(
                                                  icon: const Icon(Icons.close,
                                                      color: Colors.red,
                                                      size: 18),
                                                  onPressed: () =>
                                                      _cancelInvitation(
                                                          invitationId),
                                                ),
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                );
                              }
                              return _buildPendingShimmer(isDarkMode);
                            },
                          ),
                        ],
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds shimmer for initial screen loading
  Widget _buildInitialLoadingShimmer(bool isDarkMode) {
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shop info header shimmer
            Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 16),
            // Invite form section shimmer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 120,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Email field
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Role dropdown
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Button
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Accepted users section shimmer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 100,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...List.generate(3, (index) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Pending invitations section shimmer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 130,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...List.generate(2, (index) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingShimmer(bool isDarkMode) {
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: List.generate(3, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            height: 56,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(10),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAcceptedShimmer(bool isDarkMode) {
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: List.generate(3, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            height: 56,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(10),
            ),
          );
        }),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

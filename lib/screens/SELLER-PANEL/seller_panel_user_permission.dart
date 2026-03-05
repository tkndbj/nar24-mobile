import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';

// ─── Types ────────────────────────────────────────────────────────────────────

class _ShopMember {
  final String userId;
  final String role;
  final String displayName;

  const _ShopMember({
    required this.userId,
    required this.role,
    required this.displayName,
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Fetches display names for a list of user IDs in batches of 10.
/// Mirrors the web app's `batchFetchUserNames` helper exactly.
Future<Map<String, String>> _batchFetchUserNames(List<String> uids) async {
  if (uids.isEmpty) return {};

  final Map<String, String> result = {};

  // Chunk into groups of 10 – Firestore `whereIn` limit
  for (int i = 0; i < uids.length; i += 10) {
    final chunk = uids.sublist(i, (i + 10).clamp(0, uids.length));
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    for (final doc in snap.docs) {
      final data = doc.data();
      result[doc.id] = (data['displayName'] as String?) ?? doc.id;
    }
  }

  return result;
}

// ─── Component ────────────────────────────────────────────────────────────────

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

class _SellerPanelUserPermissionState
    extends State<SellerPanelUserPermission> {
  final _emailController = TextEditingController();
  String _selectedRole = 'viewer';
  final List<String> _roles = ['co-owner', 'editor', 'viewer'];
  bool _isSending = false;

  // Per-invitation cancelling state (mirrors web's `cancellingInvitationId`)
  String? _cancellingInvitationId;

  // Revoke state (mirrors web's `revokeTarget` / `isRevoking`)
  _ShopMember? _revokeTarget;
  bool _isRevoking = false;

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

  void _startInitSafetyTimer() {
    _initSafetyTimer = Timer(_maxInitDuration, () {
      if (mounted && !_initTimedOut) {
        debugPrint('⚠️ User permission init safety timer triggered');
        setState(() => _initTimedOut = true);
      }
    });
  }

  void _cancelInitSafetyTimer() {
    _initSafetyTimer?.cancel();
  }

  Future<void> _ensureShopSelected() async {
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

  // ── Send invitation ──────────────────────────────────────────────────────────
  //
  // Delegates entirely to the Cloud Function, mirroring the web app.
  // The CF handles email lookup, duplicate/existing-member checks, and
  // the atomic write of invitation + notification.

  Future<void> _sendInvitation() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidEmail)),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final fn = FirebaseFunctions.instance
          .httpsCallable('sendShopInvitation');
      await fn.call({
        'shopId': widget.shopId,
        'inviteeEmail': email.toLowerCase(),
        'role': _selectedRole,
      });

      if (!mounted) return;
      _showSuccessSnackbar(l10n.invitationSentSuccessfully);
      _emailController.clear();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? l10n.errorSendingInvitation(''))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorSendingInvitation(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Cancel pending invitation ────────────────────────────────────────────────
  //
  // Calls the `cancelShopInvitation` Cloud Function, mirroring the web app.
  // Previously the Flutter app deleted the Firestore doc directly.

  Future<void> _cancelInvitation(String invitationId) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _cancellingInvitationId = invitationId);
    try {
      final fn = FirebaseFunctions.instance
          .httpsCallable('cancelShopInvitation');
      await fn.call({'invitationId': invitationId});

      if (!mounted) return;
      _showSuccessSnackbar(l10n.invitationCancelled);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(e.message ?? l10n.errorCancellingInvitation(''))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(l10n.errorCancellingInvitation(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _cancellingInvitationId = null);
    }
  }

  // ── Revoke access ────────────────────────────────────────────────────────────
  //
  // Calls the `revokeShopAccess` Cloud Function, mirroring the web app.
  // Previously the Flutter app called provider.revokeUserAccess() and
  // used fragile string-matching on the returned message.

  Future<void> _confirmRevoke() async {
    if (_revokeTarget == null) return;
    final l10n = AppLocalizations.of(context);
    final target = _revokeTarget!;

    setState(() => _isRevoking = true);
    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('revokeShopAccess');
      await fn.call({
        'targetUserId': target.userId,
        'shopId': widget.shopId,
        'role': target.role,
      });

      if (!mounted) return;
      setState(() {
        _revokeTarget = null;
        _isRevoking = false;
      });
      _showSuccessSnackbar(l10n.accessRevokedSuccessfully);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isRevoking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(e.message ?? l10n.errorRevokingAccess(''))),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRevoking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.errorRevokingAccess(e.toString()))),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

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
      default:
        return Icons.visibility;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<void>(
      future: _shopLoadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !_initTimedOut) {
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
              title: Text(l10n.userPermissions,
                  style: GoogleFonts.figtree(
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black)),
              backgroundColor: isDarkMode ? null : Colors.white,
              elevation: 0,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48,
                      color: Colors.grey.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    _initTimedOut
                        ? l10n.initializationFailed
                        : '${l10n.initializationFailed}: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.figtree(
                        color:
                            isDarkMode ? Colors.white70 : Colors.grey[600]),
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
            final bool canManage = currentUserId != null &&
                (shopData?['ownerId'] == currentUserId ||
                    (shopData?['coOwners'] as List<dynamic>?)
                            ?.contains(currentUserId) ==
                        true);

            return Stack(
              children: [
                Scaffold(
                  backgroundColor: isDarkMode
                      ? const Color(0xFF1C1A29)
                      : const Color(0xFFF8F9FA),
                  appBar: AppBar(
                    title: Text(l10n.userPermissions,
                        style: GoogleFonts.figtree(
                            fontWeight: FontWeight.w600,
                            color:
                                isDarkMode ? Colors.white : Colors.black)),
                    backgroundColor: isDarkMode
                        ? const Color.fromARGB(255, 33, 31, 49)
                        : Colors.white,
                    elevation: 0,
                    shadowColor:
                        Colors.black.withOpacity(0.05),
                    surfaceTintColor: Colors.transparent,
                  ),
                  body: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─── Shop Info Header ─────────────────────
                          _buildShopHeader(selectedShopName, l10n),
                          const SizedBox(height: 16),

                          // ─── Invite Form ──────────────────────────
                          if (canManage) ...[
                            _buildInviteForm(isDarkMode, l10n),
                            const SizedBox(height: 16),
                          ],

                          // ─── Accepted Users ───────────────────────
                          _buildAcceptedUsersSection(
                              isDarkMode, l10n, canManage, currentUserId),
                          const SizedBox(height: 16),

                          // ─── Pending Invitations ──────────────────
                          _buildPendingInvitationsSection(
                              isDarkMode, l10n, canManage),
                        ],
                      ),
                    ),
                  ),
                ),

                // ─── Revoke Confirmation Modal ─────────────────────────────
                // Mirrors the web app's inline modal pattern.
                if (_revokeTarget != null) ...[
                  // Backdrop
                  GestureDetector(
                    onTap: _isRevoking
                        ? null
                        : () => setState(() => _revokeTarget = null),
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                    ),
                  ),
                  // Modal
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildRevokeModal(isDarkMode, l10n),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // ── Shop Header ──────────────────────────────────────────────────────────────

  Widget _buildShopHeader(String shopName, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.store, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(shopName,
                    style: GoogleFonts.figtree(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.managingPermissionsFor(shopName),
              style: GoogleFonts.figtree(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.9))),
        ],
      ),
    );
  }

  // ── Invite Form ──────────────────────────────────────────────────────────────

  Widget _buildInviteForm(bool isDarkMode, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color.fromARGB(255, 33, 31, 49)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.05),
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
                  color: const Color(0xFF00A86B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.person_add,
                    color: Color(0xFF00A86B), size: 18),
              ),
              const SizedBox(width: 10),
              Text(l10n.sendInvitation,
                  style: GoogleFonts.figtree(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black)),
            ],
          ),
          const SizedBox(height: 20),

          // Email field
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _isSending ? null : _sendInvitation(),
            decoration: InputDecoration(
              labelText: l10n.emailInvitee,
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.grey.withOpacity(0.3))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.grey.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFF00A86B), width: 2)),
              filled: true,
              fillColor: isDarkMode
                  ? Colors.grey.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Role dropdown
          DropdownButtonFormField<String>(
            value: _selectedRole,
            decoration: InputDecoration(
              labelText: l10n.role,
              prefixIcon: const Icon(Icons.security),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.grey.withOpacity(0.3))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.grey.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFF00A86B), width: 2)),
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
                    Icon(_getRoleIcon(role),
                        color: _getRoleColor(role), size: 16),
                    const SizedBox(width: 6),
                    Text(getLocalizedRole(
                        role, AppLocalizations.of(context))),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedRole = value);
            },
          ),
          const SizedBox(height: 20),

          // Send button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendInvitation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 16),
                        const SizedBox(width: 6),
                        Text(l10n.sendInvitation,
                            style: GoogleFonts.figtree(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Accepted Users ───────────────────────────────────────────────────────────
  //
  // Uses a single batched Firestore query (via `_batchFetchUserNames`) to fetch
  // all display names at once, mirroring the web app's `batchFetchUserNames`.
  // Previously the Flutter app used individual `FutureBuilder` calls per user
  // (N+1 Firestore reads).

  Widget _buildAcceptedUsersSection(bool isDarkMode, AppLocalizations l10n,
      bool canManage, String? currentUserId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color.fromARGB(255, 33, 31, 49)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.05),
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
                  color: const Color(0xFF00A86B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.group,
                    color: Color(0xFF00A86B), size: 18),
              ),
              const SizedBox(width: 10),
              Text(l10n.acceptedUsers,
                  style: GoogleFonts.figtree(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black)),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shops')
                .doc(widget.shopId)
                .snapshots(),
            builder: (context, shopSnap) {
              if (!shopSnap.hasData || !shopSnap.data!.exists) {
                return _buildAcceptedShimmer(isDarkMode);
              }

              final data =
                  shopSnap.data!.data() as Map<String, dynamic>;
              final String ownerId = data['ownerId'] as String;
              final List<String> coOwners =
                  (data['coOwners'] as List<dynamic>?)?.cast<String>() ??
                      [];
              final List<String> editors =
                  (data['editors'] as List<dynamic>?)?.cast<String>() ??
                      [];
              final List<String> viewers =
                  (data['viewers'] as List<dynamic>?)?.cast<String>() ??
                      [];

              // Build ordered entry list (same order as the web app)
              final entries = <Map<String, String>>[];
              entries.add({'userId': ownerId, 'role': 'owner'});
              for (final id in coOwners) {
                entries.add({'userId': id, 'role': 'co-owner'});
              }
              for (final id in editors) {
                entries.add({'userId': id, 'role': 'editor'});
              }
              for (final id in viewers) {
                entries.add({'userId': id, 'role': 'viewer'});
              }

              if (entries.isEmpty) {
                return _buildEmptyState(
                    Icons.group_outlined, l10n.noAcceptedUsers);
              }

              // Single batched fetch for all display names
              final allUids =
                  entries.map((e) => e['userId']!).toList();

              return FutureBuilder<Map<String, String>>(
                future: _batchFetchUserNames(allUids),
                builder: (context, namesSnap) {
                  if (!namesSnap.hasData) {
                    return _buildAcceptedShimmer(isDarkMode);
                  }

                  final nameMap = namesSnap.data!;
                  final members = entries
                      .map((e) => _ShopMember(
                            userId: e['userId']!,
                            role: e['role']!,
                            displayName:
                                nameMap[e['userId']!] ?? e['userId']!,
                          ))
                      .toList();

                  return ListView.separated(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isCurrentUser =
                          member.userId == currentUserId;

                      return Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _getRoleColor(member.role)
                                  .withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                member.displayName.isNotEmpty
                                    ? member.displayName[0]
                                        .toUpperCase()
                                    : '?',
                                style: GoogleFonts.figtree(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        _getRoleColor(member.role),
                                    fontSize: 16),
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(member.displayName,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: GoogleFonts.figtree(
                                        fontWeight:
                                            FontWeight.w600,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black,
                                        fontSize: 14)),
                              ),
                              if (isCurrentUser) ...[
                                const SizedBox(width: 6),
                                Text('(${l10n.youLabel})',
                                    style: GoogleFonts.figtree(
                                        fontSize: 11,
                                        color: Colors.grey[400],
                                        fontWeight:
                                            FontWeight.normal)),
                              ],
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Icon(_getRoleIcon(member.role),
                                  size: 12,
                                  color:
                                      _getRoleColor(member.role)),
                              const SizedBox(width: 3),
                              Text(
                                  getLocalizedRole(
                                      member.role, l10n),
                                  style: GoogleFonts.figtree(
                                      color: _getRoleColor(
                                          member.role),
                                      fontWeight:
                                          FontWeight.w500,
                                      fontSize: 12)),
                              if (member.role == 'owner') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1),
                                  decoration: BoxDecoration(
                                    color:
                                        const Color(0xFFFF6200),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Text('OWNER',
                                      style: GoogleFonts.figtree(
                                          fontSize: 9,
                                          color: Colors.white,
                                          fontWeight:
                                              FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          // Show revoke button only for non-owners
                          // and not for the current user — mirrors
                          // the web app's canManage check exactly.
                          trailing: canManage &&
                                  member.role != 'owner' &&
                                  !isCurrentUser
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red
                                        .withOpacity(0.1),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                        Icons.person_remove,
                                        color: Colors.red,
                                        size: 18),
                                    onPressed: () => setState(
                                        () =>
                                            _revokeTarget = member),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Pending Invitations ──────────────────────────────────────────────────────

  Widget _buildPendingInvitationsSection(
      bool isDarkMode, AppLocalizations l10n, bool canManage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color.fromARGB(255, 33, 31, 49)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.05),
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
                child: const Icon(Icons.schedule,
                    color: Colors.orange, size: 18),
              ),
              const SizedBox(width: 10),
              Text(l10n.pendingInvitations,
                  style: GoogleFonts.figtree(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color:
                          isDarkMode ? Colors.white : Colors.black)),
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
              if (!snapshot.hasData) {
                return _buildPendingShimmer(isDarkMode);
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return _buildEmptyState(
                    Icons.inbox_outlined, l10n.noPendingInvitations);
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final docData =
                      doc.data() as Map<String, dynamic>;
                  final inviteEmail =
                      docData['email'] as String? ?? 'Unknown';
                  final role =
                      docData['role'] as String? ?? 'unknown';
                  final isCancelling =
                      _cancellingInvitationId == doc.id;

                  return Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6),
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
                            inviteEmail.isNotEmpty
                                ? inviteEmail[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.figtree(
                                fontWeight: FontWeight.bold,
                                color: _getRoleColor(role),
                                fontSize: 16),
                          ),
                        ),
                      ),
                      title: Text(inviteEmail,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.figtree(
                              fontWeight: FontWeight.w600,
                              color: isDarkMode
                                  ? Colors.white
                                  : Colors.black,
                              fontSize: 14)),
                      subtitle: Row(
                        children: [
                          Icon(_getRoleIcon(role),
                              size: 12, color: _getRoleColor(role)),
                          const SizedBox(width: 3),
                          Text(getLocalizedRole(role, l10n),
                              style: GoogleFonts.figtree(
                                  color: _getRoleColor(role),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12)),
                        ],
                      ),
                      // Per-invitation spinner, mirrors web's
                      // `cancellingInvitationId` pattern exactly.
                      trailing: canManage
                          ? Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color:
                                    Colors.red.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(6),
                              ),
                              child: isCancelling
                                  ? const Padding(
                                      padding: EdgeInsets.all(9),
                                      child: CircularProgressIndicator(
                                          color: Colors.red,
                                          strokeWidth: 2),
                                    )
                                  : IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                          size: 18),
                                      onPressed: () =>
                                          _cancelInvitation(
                                              doc.id),
                                    ),
                            )
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Revoke Confirmation Modal ─────────────────────────────────────────────────
  //
  // Mirrors the web app's inline modal with a confirm / spinner button pattern.
  // Replaces the previous approach of: confirmation dialog → separate loading
  // modal → fragile string-matching on the provider result.

  Widget _buildRevokeModal(bool isDarkMode, AppLocalizations l10n) {
    final target = _revokeTarget!;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color.fromARGB(255, 33, 31, 49)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 24)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_remove_rounded,
                        color: Colors.red, size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.revokeAccess ?? 'Revoke Access',
                    style: GoogleFonts.figtree(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color:
                            isDarkMode ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.revokeAccessConfirmation ??
                        'This will remove their access to the shop.',
                    style: GoogleFonts.figtree(
                        fontSize: 13,
                        color: isDarkMode
                            ? Colors.white60
                            : Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    target.displayName,
                    style: GoogleFonts.figtree(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red),
                  ),
                ],
              ),
            ),

            // Buttons
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isRevoking
                          ? null
                          : () =>
                              setState(() => _revokeTarget = null),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                      child: Text(l10n.cancel,
                          style: GoogleFonts.figtree(
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isRevoking ? null : _confirmRevoke,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                      child: _isRevoking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2))
                          : Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(
                                    Icons.person_remove_rounded,
                                    size: 16),
                                const SizedBox(width: 6),
                                Text(l10n.revoke ?? 'Revoke',
                                    style: GoogleFonts.figtree(
                                        fontWeight:
                                            FontWeight.w600,
                                        fontSize: 13)),
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
    );
  }

  // ── Shimmer / Empty States ───────────────────────────────────────────────────

  Widget _buildEmptyState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text(text,
                style:
                    GoogleFonts.figtree(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

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
          children: [
            _shimmerBox(height: 80, radius: 12),
            const SizedBox(height: 16),
            _shimmerCard(children: [
              _shimmerBox(height: 50),
              const SizedBox(height: 14),
              _shimmerBox(height: 50),
              const SizedBox(height: 20),
              _shimmerBox(height: 44),
            ]),
            const SizedBox(height: 16),
            _shimmerCard(children: List.generate(
                3,
                (_) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _shimmerBox(height: 56)))),
            const SizedBox(height: 16),
            _shimmerCard(children: List.generate(
                2,
                (_) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _shimmerBox(height: 56)))),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox({double height = 56, double radius = 10}) =>
      Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius)),
      );

  Widget _shimmerCard({required List<Widget> children}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      );

  Widget _buildPendingShimmer(bool isDarkMode) =>
      _buildListShimmer(isDarkMode, 3);

  Widget _buildAcceptedShimmer(bool isDarkMode) =>
      _buildListShimmer(isDarkMode, 3);

  Widget _buildListShimmer(bool isDarkMode, int count) {
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
        children: List.generate(
          count,
          (_) => Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            height: 56,
            decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() =>
      "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
}
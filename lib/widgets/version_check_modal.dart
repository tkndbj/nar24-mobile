// lib/widgets/version_check_modal.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:Nar24/services/version_check_service.dart';
import 'package:Nar24/generated/l10n/app_localizations.dart';
import 'dart:ui';

/// A compact bottom sheet modal for version updates and maintenance
class VersionCheckModal extends StatefulWidget {
  final VersionCheckResult result;
  final VoidCallback? onDismiss;
  final VoidCallback? onUpdate;

  const VersionCheckModal({
    super.key,
    required this.result,
    this.onDismiss,
    this.onUpdate,
  });

  /// Shows the version check modal as a bottom sheet
  static Future<bool> show(
    BuildContext context, {
    required VersionCheckResult result,
  }) async {
    if (result.state == AppUpdateState.upToDate) {
      return false;
    }

    final shouldUpdate = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: !result.isBlocking,
      enableDrag: !result.isBlocking,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => PopScope(
        canPop: !result.isBlocking,
        onPopInvokedWithResult: (didPop, _) {
          // Mark as skipped when dismissed by any means (drag, back button, etc.)
          if (didPop && result.state == AppUpdateState.softUpdate) {
            VersionCheckService.instance
                .markVersionAsSkipped(result.latestVersion);
          }
        },
        child: VersionCheckModal(
          result: result,
          onDismiss: () {
            VersionCheckService.instance
                .markVersionAsSkipped(result.latestVersion);
            Navigator.of(context).pop(false);
          },
          onUpdate: () => Navigator.of(context).pop(true),
        ),
      ),
    );

    return shouldUpdate ?? false;
  }

  @override
  State<VersionCheckModal> createState() => _VersionCheckModalState();
}

class _VersionCheckModalState extends State<VersionCheckModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _iconController;
  Timer? _countdownTimer;
  Duration? _remainingTime;
  bool _isLaunching = false;

  // Store IDs
  static const String _androidPackageId = 'com.cts.emlak';
  static const String _iosAppId = '6752034508';

  // Button color (constant)
  static const Color _buttonOrange = Color(0xFFFF6B35);

  // Theme-aware colors
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _backgroundColor =>
      _isDark ? const Color(0xFF1C1A29) : Colors.white;

  Color get _surfaceColor =>
      _isDark ? const Color(0xFF252336) : const Color(0xFFF5F5F5);

  Color get _borderColor =>
      _isDark ? const Color(0xFF3D3A4D) : const Color(0xFFE0E0E0);

  Color get _textPrimary => _isDark ? Colors.white : Colors.black;

  Color get _textSecondary =>
      _isDark ? const Color(0xFFB8B5C8) : const Color(0xFF666666);

  @override
  void initState() {
    super.initState();

    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    if (widget.result.state == AppUpdateState.maintenance &&
        widget.result.maintenanceEndTime != null) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _updateRemainingTime();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemainingTime();
    });
  }

  void _updateRemainingTime() {
    if (widget.result.maintenanceEndTime == null) return;

    final now = DateTime.now();
    final endTime = widget.result.maintenanceEndTime!;

    if (endTime.isAfter(now)) {
      setState(() {
        _remainingTime = endTime.difference(now);
      });
    } else {
      _countdownTimer?.cancel();
      setState(() {
        _remainingTime = Duration.zero;
      });
    }
  }

  @override
  void dispose() {
    _iconController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _launchStore() async {
    if (_isLaunching) return;

    setState(() => _isLaunching = true);

    try {
      final storeUrl = widget.result.storeUrl;

      if (storeUrl != null && storeUrl.isNotEmpty) {
        final uri = Uri.parse(storeUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          widget.onUpdate?.call();
        } else {
          _showErrorSnackBar();
        }
      } else {
        await _launchDefaultStore();
        widget.onUpdate?.call();
      }
    } catch (e) {
      _showErrorSnackBar();
    } finally {
      if (mounted) {
        setState(() => _isLaunching = false);
      }
    }
  }

  Future<void> _launchDefaultStore() async {
    Uri? uri;

    if (Platform.isAndroid) {
      // Try Play Store app first
      uri = Uri.parse('market://details?id=$_androidPackageId');
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse(
            'https://play.google.com/store/apps/details?id=$_androidPackageId');
      }
    } else if (Platform.isIOS) {
      // Try App Store app first (itms-apps:// opens App Store directly)
      uri = Uri.parse('itms-apps://apps.apple.com/app/id$_iosAppId');
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse('https://apps.apple.com/app/id$_iosAppId');
      }
    }

    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showErrorSnackBar() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.versionCheckStoreError),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          if (!widget.result.isBlocking)
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildMessage(),
                if (_remainingTime != null) ...[
                  const SizedBox(height: 16),
                  _buildCountdownTimer(),
                ],
                if (widget.result.releaseNotes.isNotEmpty &&
                    widget.result.state != AppUpdateState.maintenance) ...[
                  const SizedBox(height: 16),
                  _buildReleaseNotes(),
                ],
                const SizedBox(height: 20),
                _buildActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Icon
        ScaleTransition(
          scale: CurvedAnimation(
            parent: _iconController,
            curve: Curves.elasticOut,
          ),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _getGradientColors(),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getIcon(),
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),

        // Title and version
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getTitle(context),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              if (widget.result.state != AppUpdateState.maintenance) ...[
                const SizedBox(height: 2),
                Text(
                  '${widget.result.currentVersion} → ${widget.result.latestVersion}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _getAccentColor(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _borderColor,
          width: 1,
        ),
      ),
      child: Text(
        _getMessage(context),
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: _textSecondary,
        ),
      ),
    );
  }

  Widget _buildCountdownTimer() {
    final hours = _remainingTime!.inHours;
    final minutes = _remainingTime!.inMinutes.remainder(60);
    final seconds = _remainingTime!.inSeconds.remainder(60);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.access_time_rounded,
          size: 16,
          color: _getAccentColor(),
        ),
        const SizedBox(width: 8),
        Text(
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _getAccentColor(),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildReleaseNotes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _borderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14,
                color: _getAccentColor(),
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.versionCheckWhatsNew,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _getAccentColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...widget.result.releaseNotes.take(3).map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _getAccentColor().withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: _textSecondary.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        // Primary button
        if (widget.result.state != AppUpdateState.maintenance)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLaunching ? null : _launchStore,
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _buttonOrange.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLaunching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context)!.versionCheckUpdateNow,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

        // Secondary buttons row
        if (widget.result.state == AppUpdateState.softUpdate ||
            (widget.result.isBlocking && Platform.isAndroid)) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              // Later button (soft update only)
              if (widget.result.state == AppUpdateState.softUpdate)
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: widget.onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: _textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.versionCheckLater,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),

              // Close app button (blocking states on Android)
              if (widget.result.isBlocking && Platform.isAndroid)
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => SystemNavigator.pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textSecondary,
                        side: BorderSide(
                          color: _borderColor,
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.versionCheckCloseApp,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  IconData _getIcon() {
    switch (widget.result.state) {
      case AppUpdateState.softUpdate:
        return Icons.system_update_rounded;
      case AppUpdateState.forceUpdate:
        return Icons.warning_amber_rounded;
      case AppUpdateState.maintenance:
        return Icons.build_circle_rounded;
      case AppUpdateState.upToDate:
        return Icons.check_circle_rounded;
    }
  }

  String _getTitle(BuildContext context) {
    switch (widget.result.state) {
      case AppUpdateState.softUpdate:
        return AppLocalizations.of(context)!.versionCheckUpdateAvailable;
      case AppUpdateState.forceUpdate:
        return AppLocalizations.of(context)!.versionCheckUpdateRequired;
      case AppUpdateState.maintenance:
        return AppLocalizations.of(context)!.versionCheckMaintenance;
      case AppUpdateState.upToDate:
        return AppLocalizations.of(context)!.versionCheckUpToDate;
    }
  }

  String _getMessage(BuildContext context) {
    if (widget.result.state == AppUpdateState.maintenance) {
      return widget.result.maintenanceMessage ??
          AppLocalizations.of(context)!.versionCheckMaintenanceDefault;
    }

    return widget.result.updateMessage ??
        AppLocalizations.of(context)!.versionCheckUpdateDefault;
  }

  Color _getAccentColor() {
    switch (widget.result.state) {
      case AppUpdateState.softUpdate:
        return _buttonOrange;
      case AppUpdateState.forceUpdate:
        return const Color(0xFFE53935);
      case AppUpdateState.maintenance:
        return const Color(0xFFFF9800);
      case AppUpdateState.upToDate:
        return const Color(0xFF2196F3);
    }
  }

  List<Color> _getGradientColors() {
    switch (widget.result.state) {
      case AppUpdateState.softUpdate:
        return [const Color(0xFFFF6B35), const Color(0xFFE91E63)];
      case AppUpdateState.forceUpdate:
        return [const Color(0xFFEF5350), const Color(0xFFE53935)];
      case AppUpdateState.maintenance:
        return [const Color(0xFFFFA726), const Color(0xFFFF9800)];
      case AppUpdateState.upToDate:
        return [const Color(0xFF42A5F5), const Color(0xFF2196F3)];
    }
  }
}

/// Extension to make the modal easier to call from anywhere
extension VersionCheckModalExtension on BuildContext {
  Future<void> showVersionCheckIfNeeded({
    required String languageCode,
    bool forceCheck = false,
  }) async {
    try {
      final result = await VersionCheckService.instance.checkVersion(
        languageCode: languageCode,
        forceRefresh: forceCheck,
      );

      if (result.requiresAction) {
        await VersionCheckModal.show(this, result: result);
      }
    } catch (e) {
      debugPrint('Error showing version check: $e');
    }
  }
}

/// Wrapper widget that automatically checks version on first build
class VersionCheckWrapper extends StatefulWidget {
  final Widget child;
  final String languageCode;
  final Duration checkDelay;

  const VersionCheckWrapper({
    super.key,
    required this.child,
    required this.languageCode,
    this.checkDelay = const Duration(milliseconds: 500),
  });

  @override
  State<VersionCheckWrapper> createState() => _VersionCheckWrapperState();
}

class _VersionCheckWrapperState extends State<VersionCheckWrapper> {
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    _scheduleVersionCheck();
  }

  void _scheduleVersionCheck() {
    Future.delayed(widget.checkDelay, () {
      if (mounted && !_hasChecked) {
        _performVersionCheck();
      }
    });
  }

  Future<void> _performVersionCheck() async {
    _hasChecked = true;

    try {
      final result = await VersionCheckService.instance.checkVersion(
        languageCode: widget.languageCode,
      );

      if (result.requiresAction && mounted) {
        await VersionCheckModal.show(context, result: result);
      }
    } catch (e) {
      debugPrint('Version check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

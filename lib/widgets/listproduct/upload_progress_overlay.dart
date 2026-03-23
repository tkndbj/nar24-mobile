import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'upload_progress_state.dart';

/// Full-screen, non-dismissible overlay shown during file upload + submission.
///
/// Uses a dedicated [AnimationController] so the progress bar interpolates
/// smoothly between any two values regardless of how fast setState fires.
/// Place as the last child of a [Stack] so it covers everything.
class UploadProgressOverlay extends StatefulWidget {
  final UploadState state;

  const UploadProgressOverlay({Key? key, required this.state})
      : super(key: key);

  @override
  State<UploadProgressOverlay> createState() => _UploadProgressOverlayState();
}

class _UploadProgressOverlayState extends State<UploadProgressOverlay>
    with TickerProviderStateMixin {
  // ── Progress bar animation ────────────────────────────────────────
  late AnimationController _barController;
  late Animation<double> _barAnimation;

  // ── Icon rotation (uploading phase only) ─────────────────────────
  late AnimationController _iconController;

  @override
  void initState() {
    super.initState();

    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _barAnimation = Tween<double>(
      begin: 0.0,
      end: widget.state.fraction,
    ).animate(CurvedAnimation(
      parent: _barController,
      curve: Curves.easeOut,
    ));
    _barController.forward();

    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.state.phase == UploadPhase.uploading) {
      _iconController.repeat();
    }
  }

  @override
  void didUpdateWidget(UploadProgressOverlay old) {
    super.didUpdateWidget(old);

    // Smoothly animate bar from its current visual position to the new target.
    if (widget.state.fraction != old.state.fraction) {
      _barAnimation = Tween<double>(
        begin: _barAnimation.value, // from wherever the bar visually is now
        end: widget.state.fraction,
      ).animate(CurvedAnimation(
        parent: _barController,
        curve: Curves.easeOut,
      ));
      _barController.forward(from: 0.0);
    }

    // Toggle icon rotation when phase changes.
    if (widget.state.phase != old.state.phase) {
      if (widget.state.phase == UploadPhase.uploading) {
        _iconController.repeat();
      } else {
        _iconController.stop();
        _iconController.reset();
      }
    }
  }

  @override
  void dispose() {
    _barController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return AbsorbPointer(
      // Swallow all taps so nothing behind can be interacted with.
      child: Container(
        color: Colors.black.withOpacity(0.72),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color.fromARGB(255, 33, 31, 49)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPhaseIcon(),
                const SizedBox(height: 20),
                _buildTitle(isDark, l10n),
                const SizedBox(height: 6),
                _buildSubtitle(isDark, l10n),
                const SizedBox(height: 24),
                _buildProgressBar(isDark),
                const SizedBox(height: 10),
                _buildProgressDetails(isDark, l10n),
                const SizedBox(height: 20),
                _buildDoNotCloseWarning(isDark, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

Widget _buildProgressBar(bool isDark) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      AnimatedBuilder(
        animation: _barAnimation,
        builder: (context, _) {
          final pct = (_barAnimation.value * 100).toStringAsFixed(0);
          return Text('$pct%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF00A86B)));
        },
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 10,
          width: double.infinity,
          color: isDark ? Colors.white12 : Colors.grey.shade200,
          child: AnimatedBuilder(
            animation: _barAnimation,
            builder: (context, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _barAnimation.value.clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF00A86B), Color(0xFF00C574)]),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

  // ── Phase icon ────────────────────────────────────────────────────

Widget _buildPhaseIcon() {
  final IconData icon = widget.state.phase == UploadPhase.uploading
      ? Icons.cloud_upload_outlined
      : Icons.check_rounded;

  final container = Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF00A86B), Color(0xFF00C574)],
      ),
      borderRadius: BorderRadius.circular(50),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF00A86B).withOpacity(0.35),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: 32),
  );

  if (widget.state.phase == UploadPhase.uploading) {
    return RotationTransition(turns: _iconController, child: container);
  }
  return container;
}

Widget _buildTitle(bool isDark, AppLocalizations l10n) {
  final String text = widget.state.phase == UploadPhase.uploading
      ? l10n.uploadOverlayUploading
      : l10n.uploadOverlayFinalizing;

  return Text(
    text,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white : Colors.black87,
      letterSpacing: -0.3,
    ),
    textAlign: TextAlign.center,
  );
}

Widget _buildSubtitle(bool isDark, AppLocalizations l10n) {
  final String text;
  if (widget.state.phase == UploadPhase.uploading) {
    text = widget.state.totalFiles == 0
        ? l10n.uploadOverlaySendingFiles
        : l10n.uploadOverlayFilesUploaded(widget.state.uploadedFiles, widget.state.totalFiles);
  } else {
    text = l10n.uploadOverlayAlmostDone;
  }

  return Text(
    text,
    style: TextStyle(
      fontSize: 14,
      color: isDark ? Colors.white60 : Colors.grey.shade600,
    ),
    textAlign: TextAlign.center,
  );
}

Widget _buildProgressDetails(bool isDark, AppLocalizations l10n) {
  final Color textColor = isDark ? Colors.white38 : Colors.grey.shade500;

  if (widget.state.phase == UploadPhase.uploading &&
      widget.state.totalBytes > 0) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l10n.uploadOverlayFilesProgress(widget.state.uploadedFiles, widget.state.totalFiles),
          style: TextStyle(fontSize: 12, color: textColor),
        ),
        Text(
          '${UploadState.formatBytes(widget.state.bytesTransferred)} '
          '/ ${UploadState.formatBytes(widget.state.totalBytes)}',
          style: TextStyle(fontSize: 12, color: textColor),
        ),
      ],
    );
  }

  return SizedBox(
    height: 16,
    child: widget.state.phase == UploadPhase.submitting
        ? Center(
            child: Text(
              l10n.uploadOverlaySavingToDatabase,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          )
        : const SizedBox.shrink(),
  );
}

  // ── Do-not-close warning ──────────────────────────────────────────

  Widget _buildDoNotCloseWarning(bool isDark, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: isDark ? Colors.white30 : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          l10n.uploadOverlayDoNotClose,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white30 : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}
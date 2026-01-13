import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../generated/l10n/app_localizations.dart';
import '../auth_service.dart';
import 'agreement_modal.dart';

class LoginPromptModal extends StatelessWidget {
  final AuthService authService;

  const LoginPromptModal({Key? key, required this.authService})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return CupertinoActionSheet(
      title: Text(
        AppLocalizations.of(context).login,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      actions: [
        // Email and Password Button
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/login');
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/gmail.png',
                width: 21,
                height: 21,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).loginWithEmailandPassword,
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
        // Google Sign-In Button
        CupertinoActionSheetAction(
          onPressed: () async {
            // Capture the root navigator BEFORE any async operations
            final rootNavigator = Navigator.of(context, rootNavigator: true);

            try {
              final result = await authService.signInWithGoogle();
              final User? user = result['user'];

              if (user != null) {
                // Pop the login modal first
                Navigator.of(context).pop();

                // Check if this Google user needs to accept agreements
                final hasAccepted = await AgreementModal.hasAcceptedAgreements(user.uid);
                if (!hasAccepted) {
                  // Small delay to ensure the pop animation completes
                  await Future.delayed(const Duration(milliseconds: 300));

                  // Show agreement modal using the captured root navigator context
                  if (rootNavigator.mounted) {
                    await AgreementModal.show(rootNavigator.context);
                  }
                }
              } else {
                Navigator.of(context).pop();
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Login failed: $e')),
              );
            }
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/google_icon.png',
                width: 20,
                height: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).signInWithGoogle,
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
        // Apple Sign-In Button (iOS only)
        if (Platform.isIOS)
          CupertinoActionSheetAction(
            onPressed: () async {
              // Capture the root navigator BEFORE any async operations
              final rootNavigator = Navigator.of(context, rootNavigator: true);

              try {
                final result = await authService.signInWithApple();
                final User? user = result['user'];

                if (user != null) {
                  // Pop the login modal first
                  Navigator.of(context).pop();

                  // Check if this Apple user needs to accept agreements
                  final hasAccepted = await AgreementModal.hasAcceptedAgreements(user.uid);
                  if (!hasAccepted) {
                    // Small delay to ensure the pop animation completes
                    await Future.delayed(const Duration(milliseconds: 300));

                    // Show agreement modal using the captured root navigator context
                    if (rootNavigator.mounted) {
                      await AgreementModal.show(rootNavigator.context);
                    }
                  }
                } else {
                  Navigator.of(context).pop();
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Login failed: $e')),
                );
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.apple,
                  size: 22,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).appleLoginButton,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () {
          Navigator.of(context).pop();
        },
        child: Text(
          AppLocalizations.of(context).cancel,
          style: const TextStyle(
            fontSize: 16,
            color: CupertinoColors.destructiveRed,
          ),
        ),
      ),
    );
  }
}
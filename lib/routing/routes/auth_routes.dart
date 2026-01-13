// lib/routing/routes/auth_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import your screens
import '../../screens/AUTHENTICATION/login_screen.dart';
import '../../screens/AUTHENTICATION/registration_screen.dart';
import '../../screens/AUTHENTICATION/email_verification_screen.dart';
import '../../screens/AUTHENTICATION/forgot_password_screen.dart';
import '../../screens/AUTHENTICATION/complete_name_screen.dart';

class AuthRoutes {
  // Reusable slide transition
  static Widget _slideTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    final tween = Tween(begin: begin, end: end)
        .chain(CurveTween(curve: Curves.easeInOut));
    return SlideTransition(
      position: animation.drive(tween),
      child: child,
    );
  }

  static List<RouteBase> get routes {
    return [
      // ==================== LOGIN ====================

      // Login Screen
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: LoginScreen(
              showVerificationMessage:
                  extra?['showVerificationMessage'] ?? false,
              email: extra?['email'],
              password: extra?['password'],
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== REGISTRATION ====================

      // Registration Screen
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const RegistrationScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/complete-name',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          // Fallback to currentUser when router redirects (no extra params)
          final userId = extra?['userId'] as String? ??
              FirebaseAuth.instance.currentUser?.uid ??
              '';
          return CompleteNameScreen(userId: userId);
        },
      ),

      // ==================== EMAIL VERIFICATION ====================

      // Email Verification Screen
      GoRoute(
        path: '/email-verification',
        name: 'email-verification',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const EmailVerificationScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== PASSWORD RECOVERY ====================

      // Forgot Password Screen
      GoRoute(
        path: '/forgot_password',
        name: 'forgot-password',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ForgotPasswordScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}

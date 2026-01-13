// lib/services/two_factor_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TwoFactorService {
  static final TwoFactorService _instance = TwoFactorService._internal();
  factory TwoFactorService() => _instance;
  TwoFactorService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _fnsEmail =
      FirebaseFunctions.instanceFor(region: 'europe-west2'); // email 2FA
  final FirebaseFunctions _fnsTotp =
      FirebaseFunctions.instanceFor(region: 'europe-west3'); // TOTP

  // Ephemeral flow state
  String? _currentType; // 'setup' | 'login' | 'disable'
  String? _currentMethod; // 'totp'  | 'email'
  String? _otpauthUri; // Setup QR / deep-link only

  // Public state (read-only)
  String? get currentMethod => _currentMethod;
  String? get otpauthUri => _otpauthUri;

  /// Client-side read to show UI hints (server güncelliyor)
  Future<bool> is2FAEnabled() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      return (doc.data()?['twoFactorEnabled'] ?? false) == true;
    } catch (_) {
      return false;
    }
  }

  /// TOTP aktif mi? (rules’a takılmadan backend’den soruyoruz)
  Future<bool> isTotpEnabled() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final callable = _fnsTotp.httpsCallable('hasTotp');
      final res = await callable.call({});
      final data = res.data;
      if (data is Map) {
        return (data['enabled'] ?? false) == true;
      }
      return false;
    } catch (_) {
      // emin değilsek e-posta fallback’a izin verelim
      return false;
    }
  }

  // ───────────────────────────── Email 2FA helpers ─────────────────────────────

  Future<Map<String, dynamic>> _startEmail2FA(String type) async {
      final callable = _fnsEmail.httpsCallable('startEmail2FA');
    final res = await callable.call({'type': type});
    final data =
        (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
    final success = data['success'] == true;

    if (success) _currentMethod = 'email';

    return {
      'success': success,
      'method': 'email',
      'message':
          data['message'] ?? (success ? 'emailCodeSent' : 'twoFactorInitError'),
    };
  }

  Future<Map<String, dynamic>> _verifyEmail2FA(
    String code,
    String action, // 'enable' | 'login' | 'disable'
  ) async {
    final callable = _fnsEmail.httpsCallable('verifyEmail2FA');
    final res = await callable.call({'code': code, 'action': action});
    final data =
        (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};

    return {
      'success': data['success'] == true,
      'message': data['message'] ?? 'twoFactorVerificationError',
      if (data.containsKey('remaining')) 'remaining': data['remaining'],
    };
  }

  // ───────────────────────────────── SETUP ─────────────────────────────────

  Future<Map<String, dynamic>> start2FASetup() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    _currentType = 'setup';

    try {
      final callable = _fnsTotp.httpsCallable('createTotpSecret');
      final res = await callable.call({});
      final data =
          (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};

      _otpauthUri = (data['otpauth'] as String?) ?? '';
      final secret = (data['secretBase32'] as String?) ?? '';
      _currentMethod = 'totp';

      return {
        'success': true,
        'method': 'totp',
        'otpauth': _otpauthUri,
        'secretBase32': secret,
        'message': 'totp_setup_started',
      };
    } catch (_) {
      // fallback: email 2FA (setup = enable)
      return await _startEmail2FA('setup');
    }
  }

  Future<Map<String, dynamic>> verify2FASetup(String enteredCode) async {
    final code = enteredCode.trim().replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      return {'success': false, 'message': 'invalidCodeFormat'};
    }

    if (_currentMethod == 'totp') {
      try {
        final callable = _fnsTotp.httpsCallable('verifyTotp');
        await callable.call({'code': code});
        _otpauthUri = null; // sensitive cleanup
        return {'success': true, 'message': 'twoFactorEnabledSuccess'};
      } catch (_) {
        return {'success': false, 'message': 'invalidCode'};
      }
    }

    // Email flow for setup should use 'enable' as action
    return await _verifyEmail2FA(code, 'setup');
  }

  // ───────────────────────────────── LOGIN ────────────────────────────────

  Future<Map<String, dynamic>> start2FALogin() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    _currentType = 'login';

    if (await isTotpEnabled()) {
      _currentMethod = 'totp';
      return {
        'success': true,
        'method': 'totp',
        'message': 'enterAuthenticatorCode',
      };
    }

    // email
    _currentMethod = 'email';
    return {'success': true, 'method': 'email', 'message': 'emailAvailable'};
  }

  Future<Map<String, dynamic>> verify2FALogin(String enteredCode) async {
    final code = enteredCode.trim().replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      return {'success': false, 'message': 'invalidCodeFormat'};
    }

    if (_currentMethod == 'totp') {
      try {
        final callable = _fnsTotp.httpsCallable('verifyTotp');
        await callable.call({'code': code});
        return {'success': true, 'message': 'twoFactorLoginSuccess'};
      } catch (_) {
        return {'success': false, 'message': 'invalidCode'};
      }
    }

    // For email verification during login, pass 'login' as action
    return await _verifyEmail2FA(
        code, 'login'); // Make sure this is 'login', not 'enable'
  }

  // ─────────────────────────────── DISABLE ────────────────────────────────

  Future<Map<String, dynamic>> start2FADisable() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    _currentType = 'disable';

    if (await isTotpEnabled()) {
      _currentMethod = 'totp';
      return {
        'success': true,
        'method': 'totp',
        'message': 'enterAuthenticatorCodeToDisable',
      };
    }

    // email
    return await _startEmail2FA('disable');
  }

  Future<Map<String, dynamic>> verify2FADisable(String enteredCode) async {
    final code = enteredCode.trim().replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      return {'success': false, 'message': 'invalidCodeFormat'};
    }

    if (_currentMethod == 'totp') {
      try {
        final verify = _fnsTotp.httpsCallable('verifyTotp');
        await verify.call({'code': code});

        final disable = _fnsTotp.httpsCallable('disableTotp');
        await disable.call({});

        return {'success': true, 'message': 'twoFactorDisabledSuccess'};
      } catch (_) {
        return {'success': false, 'message': 'invalidCode'};
      }
    }

    // Email flow for disable uses 'disable' as action
    return await _verifyEmail2FA(code, 'disable');
  }

  // ─────────────────────────────── RESEND ─────────────────────────────────

  Future<Map<String, dynamic>> resendVerificationCode() async {
    if (_currentMethod == 'totp') {
      return {'success': false, 'message': 'resendNotApplicableForTotp'};
    }
    // default 'login', setup akışında backend 'enable' bekler
    final type = _currentType ?? 'login'; // 'login' | 'setup' | 'disable'
    return await _resendEmail2FA(type);
  }

  Future<Map<String, dynamic>> _resendEmail2FA([String? type]) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final normalized = (type ?? _currentType ?? 'login');

    try {
      final callable = _fnsEmail.httpsCallable('resendEmail2FA');
      final res = await callable.call({'type': normalized});
      final data =
          (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
      final success = data['success'] == true;

      if (success) _currentMethod = 'email';

      return {
        'success': success,
        'message': data['message'] ??
            (success ? 'emailCodeSent' : 'twoFactorResendError'),
      };
    } on FirebaseFunctionsException {
      // throttling vb. durumlar
      return {'success': false, 'message': 'pleasewait30seconds'};
    } catch (_) {
      return {'success': false, 'message': 'twoFactorResendError'};
    }
  }

  // ───────────────────────────────── FALLBACK ─────────────────────────────────

  Future<Map<String, dynamic>> useEmailFallback([String? type]) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Determine the effective type
    final effectiveType = type ?? (_currentType ?? 'login');

    try {
     // Keep action names consistent with backend: 'login' | 'setup' | 'disable'
      final backendType = effectiveType;


      // Call the backend with the normalized type
      final callable = _fnsEmail.httpsCallable('startEmail2FA');
      final res = await callable.call({'type': backendType});
      final data =
          (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
      final success = data['success'] == true;

      if (success) {
        _currentMethod = 'email'; // Switch to email method
      }

      return {
        'success': success,
        'method': 'email',
        'message': data['message'] ??
            (success ? 'emailCodeSent' : 'twoFactorInitError'),
      };
    } on FirebaseFunctionsException catch (e) {
      // Handle Firebase Functions specific errors
      return {'success': false, 'message': e.message ?? 'twoFactorInitError'};
    } catch (_) {
      return {'success': false, 'message': 'twoFactorInitError'};
    }
  }
}

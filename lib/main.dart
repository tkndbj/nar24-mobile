// lib/main.dart

import 'dart:async';
import 'config/firebase_config.dart';
import 'package:Nar24/providers/favorite_product_provider.dart';
import 'package:Nar24/providers/market_banner_provider.dart';
import 'package:Nar24/providers/special_filter_provider_market.dart';
import 'package:Nar24/providers/special_filter_provider_teras.dart';
import 'package:Nar24/providers/product_repository.dart';
import 'package:Nar24/providers/market_dynamic_filter_provider.dart';
import 'package:Nar24/providers/product_detail_provider.dart';
import 'package:Nar24/screens/PRODUCT-SCREENS/product_detail_screen.dart';
import 'package:Nar24/providers/profile_provider.dart';
import 'package:Nar24/auth_service.dart';
import 'services/app_lifecycle_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:timeago/timeago.dart' show EnMessages, TrMessages, RuMessages;
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';
import 'theme.dart';
import 'user_provider.dart';
import 'generated/l10n/app_localizations.dart';
import 'providers/market_provider.dart';
import '/providers/stat_provider.dart';
import '/providers/teras_provider.dart';
import 'providers/badge_provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'package:flutter/foundation.dart';
import 'providers/shop_widget_provider.dart';
import 'splash_screen.dart';
import 'services/deep_link_handler.dart';
import 'services/market_layout_service.dart';
import 'package:flutter/services.dart';
import 'widgets/boostedVisibilityWrapper.dart';
import 'providers/boosted_rotation_provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'routing/routes/app_router.dart';
import 'dart:ui';
import 'package:Nar24/utils/memory_manager.dart';
import 'package:Nar24/services/click_tracking_service.dart';
import 'services/user_activity_service.dart';
import 'services/version_check_service.dart';
import 'widgets/version_check_modal.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'services/sales_config_service.dart';

/// Background message handler for FCM.
///
/// IMPORTANT: Do NOT show local notifications here when using FCM with a
/// `notification` payload. The system automatically displays the notification
/// from the FCM payload. Creating a local notification here would cause duplicates.
///
/// This handler is kept for:
/// - Data-only message processing (if needed in the future)
/// - Background data sync operations
/// - Analytics/logging of received messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for any background operations
  await Firebase.initializeApp();

  // Log for debugging (only in debug mode)
  if (kDebugMode) {
    debugPrint('📩 Background FCM received: ${message.messageId}');
    debugPrint('   Data: ${message.data}');
  }

  // The FCM `notification` payload automatically shows a system notification.
  // Route handling is done via onMessageOpenedApp when user taps the notification.
  // No need to create a local notification here - that would cause duplicates.
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool firebaseInitialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the app lifecycle manager FIRST
  // This coordinates all provider lifecycles for smooth background/foreground transitions
  AppLifecycleManager.instance.initialize();

  // 🔒 NOW add orientation lock AFTER binding initialization
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  timeago.setLocaleMessages('en', EnMessages());
  timeago.setLocaleMessages('tr', TrMessages());
  timeago.setLocaleMessages('ru', RuMessages());
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? localeCode = prefs.getString('locale');
  if (localeCode == null) {
  localeCode = 'tr'; // Your default language
  await prefs.setString('locale', localeCode);
}
  bool isDarkMode = prefs.getBool('isDarkMode') ?? false;
  bool _firebaseInitialized = false;

  try {
    if (!_firebaseInitialized && Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseInitialized = true;

      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);

      // Initialize Firebase Analytics
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

      // ✅ OPTIMIZED: Limited cache to prevent storage bloat
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024, // 100 MB (was unlimited)
      );
      FirebaseFunctions.instanceFor(region: 'europe-west3');

      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      );

      // ✅ ADD CRASHLYTICS HERE
      if (!kIsWeb) {
        FlutterError.onError = (details) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
          Sentry.captureException(details.exception, stackTrace: details.stack);
        };

        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          Sentry.captureException(error, stackTrace: stack);
          return true;
        };
      }

      if (kDebugMode) {
        print('Firebase initialized with europe-west3 Functions.');
      }
      VersionCheckService.instance.initialize().catchError((e) {
        if (kDebugMode) {
          debugPrint('⚠️ VersionCheckService initialization failed: $e');
        }
      });
    }

    await ClickTrackingService.instance.initialize();
    if (kDebugMode) {
      debugPrint('✅ ClickTrackingService initialized');
    }

    await UserActivityService.instance.initialize();
    if (kDebugMode) {
      debugPrint('✅ UserActivityService initialized');
    }

    SalesConfigService().initialize();
    if (kDebugMode) {
      debugPrint('✅ SalesConfigService initialized');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      defaultPresentAlert: true, // 👈 ADD THIS
      defaultPresentSound: true, // 👈 ADD THIS
      defaultPresentBadge: true, // 👈 ADD THIS
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null) {
          GoRouter.of(MyApp.navigatorKey.currentContext!).push(route);
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 🔧 FIX: Configure foreground notification behavior
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false, // Don't auto-show when app is open
      badge: true, // Still update badge count
      sound: false, // Don't play sound when app is open
    );

    // Handle foreground messages - app is open, no system notification shown
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('📱 Foreground FCM received: ${message.messageId}');
      }

      // When app is in foreground, FCM doesn't show system notification.
      // You could show an in-app banner/snackbar here if desired.
      final route = message.data['route'] as String?;
      if (route != null && kDebugMode) {
        debugPrint('📍 Route available: $route');
      }

      // Note: When app is backgrounded/killed, FCM's notification payload
      // automatically shows a system notification. Tap handling is done via
      // onMessageOpenedApp (background) or getInitialMessage (cold start).
    });
  } catch (e, stacktrace) {
    if (kDebugMode) {
      debugPrint("Firebase initialization or App Check error: ${e.toString()}");
      debugPrint("Stacktrace: $stacktrace");
    }
  }

  MemoryManager().setupMemoryManagement();

  await SentryFlutter.init((options) {
    options.dsn =
        'https://a08336b4ac08df701c201cd4d7bac209@o4510244091985920.ingest.de.sentry.io/4510544590340177';
    options.tracesSampleRate = 0.0;
    options.environment = kDebugMode ? 'development' : 'production';
  },
      appRunner: () => runApp(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<LocaleProvider>(
                  create: (_) => LocaleProvider(
                    localeCode != null
                        ? Locale(localeCode)
                        : const Locale('tr'),
                  ),
                ),
                ChangeNotifierProvider<ThemeProvider>(
                  create: (_) => ThemeProvider(isDarkMode: isDarkMode),
                ),
                ChangeNotifierProvider<UserProvider>(
                    create: (_) => UserProvider()),
                ChangeNotifierProvider<BadgeProvider>(
                    create: (_) => BadgeProvider()),
                ChangeNotifierProvider<MarketProvider>(
                  create: (_) => MarketProvider(
                      Provider.of<UserProvider>(_, listen: false)),
                ),
                ChangeNotifierProvider<BoostedRotationProvider>(
                  create: (_) => BoostedRotationProvider()..initialize(),
                  lazy: false, // Add this - critical!
                ),
                ChangeNotifierProvider(create: (_) => MarketBannerProvider()),
                ChangeNotifierProvider(create: (_) => DynamicFilterProvider()),
                ChangeNotifierProvider(
                  create: (context) => SpecialFilterProviderMarket(
                    Provider.of<UserProvider>(context, listen: false),
                  ),
                ),
                ChangeNotifierProvider(
                  create: (context) => SpecialFilterProviderTeras(
                    Provider.of<UserProvider>(context, listen: false),
                  ),
                ),
                ChangeNotifierProvider(create: (_) => ShopWidgetProvider()),
                ChangeNotifierProvider<StatProvider>(
                    create: (_) => StatProvider()),
                Provider<FirebaseAuth>(create: (_) => FirebaseAuth.instance),
                Provider<FirebaseFirestore>(
                    create: (_) => FirebaseFirestore.instance),
                Provider<AuthService>(
                  create: (_) => AuthService(
                    googleServerClientId: FirebaseConfig.googleServerClientId,
                    iosClientId: FirebaseConfig.googleIosClientId,
                  ),
                ),
                ChangeNotifierProvider(
                  create: (context) => CartProvider(
                    context.read<FirebaseAuth>(),
                    context.read<FirebaseFirestore>(),
                  ),
                ),
                ChangeNotifierProvider(
                  create: (context) => FavoriteProvider(
                    context.read<FirebaseAuth>(),
                    context.read<FirebaseFirestore>(),
                  ),
                ),
                ChangeNotifierProvider<TerasProvider>(
                  create: (_) => TerasProvider(
                      Provider.of<UserProvider>(_, listen: false)),
                ),
                Provider<ProductRepository>(
                  create: (_) => ProductRepository(FirebaseFirestore.instance),
                ),
                ChangeNotifierProvider<MarketLayoutService>(
                  create: (_) => MarketLayoutService(),
                ),
                ChangeNotifierProvider<ProfileProvider>(
                  create: (_) => ProfileProvider(),
                ),
              ],
              child: const MyApp(),
            ),
          ));
}

Future<void> _requestPushPermission() async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      if (kDebugMode) {
        print('iOS user granted permission: ${settings.authorizationStatus}');
      }
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      if (kDebugMode) {
        print(
          'User declined or has not accepted permission for notifications.',
        );
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error requesting push permission: $e');
    }
  }
}

class LocaleProvider extends ChangeNotifier {
  Locale _locale;

  LocaleProvider(this._locale);

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!L10n.supportedLocales.contains(locale)) return;
    _locale = locale;
    notifyListeners();
    persistLocale(locale);
  }

  Future<void> persistLocale(Locale locale) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late GoRouter _router;
  bool _routerInitialized = false;
  bool _deepLinkInitialized = false;
  Timer? _memoryCheckTimer;
  bool _wasLoadingLastFrame = true; // Track loading state
  bool _minSplashTimeElapsed = false;
  static const Duration _minSplashDuration = Duration(seconds: 2);
  bool _versionCheckCompleted = false;
  bool _versionCheckInProgress = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.delayed(_minSplashDuration, () {
      if (mounted) setState(() => _minSplashTimeElapsed = true);
    });

    _configureNotificationDeepLinks();

    // Initialize ImpressionBatcher with MarketProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeInitializeDeepLinkHandler();

      // Initialize the ImpressionBatcher
      final marketProvider = Provider.of<MarketProvider>(
        context,
        listen: false,
      );
      ImpressionBatcher().initialize(marketProvider);
    });

    Future.delayed(const Duration(seconds: 5), () {
      _requestPushPermission();
    });
  }

  Future<void> _safeInitializeDeepLinkHandler() async {
    if (_deepLinkInitialized) return; // Prevent double initialization

    try {
      // Wait for context to be ready
      var attempts = 0;
      while (attempts < 10 &&
          (!mounted || MyApp.navigatorKey.currentContext == null)) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (mounted && MyApp.navigatorKey.currentContext != null) {
        await DeepLinkHandler.initialize(MyApp.navigatorKey.currentContext!);
        _deepLinkInitialized = true;
        if (kDebugMode) {
          debugPrint('✅ Deep link handler initialized successfully');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '❌ Failed to initialize deep link handler: Context not ready',
          );
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Deep link handler initialization error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      // Don't rethrow - let the app continue without deep links
    }
  }

  Future<void> _performVersionCheck(BuildContext context) async {
    if (_versionCheckCompleted || _versionCheckInProgress) return;

    _versionCheckInProgress = true;

    try {
      // ✅ Get locale BEFORE any async operations
      final localeProvider =
          Provider.of<LocaleProvider>(context, listen: false);
      final languageCode = localeProvider.locale.languageCode;

      await Future.delayed(const Duration(milliseconds: 300));

      // ✅ Check mounted BEFORE using any context
      if (!mounted) return;

      final result = await VersionCheckService.instance.checkVersion(
        languageCode: languageCode,
      );

      if (kDebugMode) {
        debugPrint('🔍 Version check result: ${result.state}');
      }

      // ✅ Check mounted again after second async operation
      if (!mounted) return;

      if (result.requiresAction) {
        // ✅ Get navContext AFTER mounted check, right before use
        final navContext = MyApp.navigatorKey.currentContext;
        if (navContext != null && navContext.mounted) {
          await VersionCheckModal.show(navContext, result: result);
        }
      }

      _versionCheckCompleted = true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Version check error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      _versionCheckCompleted = true;
    } finally {
      _versionCheckInProgress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // NOTE: Provider lifecycle management is handled by AppLifecycleManager
    // This method only handles non-provider related lifecycle tasks

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush pending data before going to background
      ImpressionBatcher().flush();
      UserActivityService.instance.forceFlush();
      ClickTrackingService.instance.dispose();

      // Clear static caches
      try {
        ProductDetailProvider.clearAllStaticCaches();
        ProductDetailScreen.clearStaticCaches();

        if (kDebugMode) {
          debugPrint('🧹 Cleared all product detail caches');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error clearing caches: $e');
        }
      }
    }

    if (state == AppLifecycleState.resumed) {
      // Memory cleanup is now handled efficiently after provider resume
      // Schedule it with a slight delay to avoid competing with provider resume
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          MemoryManager().checkAndClearIfNeeded();
        }
      });

      // Re-initialize deep link handler if needed
      if (!_deepLinkInitialized) {
        if (kDebugMode) {
          debugPrint(
            'App resumed, attempting to reinitialize deep link handler',
          );
        }
        _safeInitializeDeepLinkHandler();
      }
      _versionCheckCompleted = false;
    }
  }

  void _configureNotificationDeepLinks() {
    // 1) Cold start - handle with delay to ensure router is ready
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg?.data['route'] != null) {
        final route = msg!.data['route']!;
        if (kDebugMode) {
          debugPrint('🔗 Cold start with route: $route');
        }

        // Wait for router to be ready
        Future.delayed(const Duration(milliseconds: 1000), () {
          try {
            if (mounted && MyApp.navigatorKey.currentContext != null) {
              GoRouter.of(MyApp.navigatorKey.currentContext!).push(route);
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ Error navigating from cold start: $e');
            }
          }
        });
      }
    }).catchError((e) {
      if (kDebugMode) {
        debugPrint('❌ Error getting initial message: $e');
      }
    });

    // 2) Background tap - also add error handling
    FirebaseMessaging.onMessageOpenedApp.listen(
      (msg) {
        final route = msg.data['route'];
        if (route != null) {
          if (kDebugMode) {
            debugPrint('🔗 Background tap with route: $route');
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              if (mounted && MyApp.navigatorKey.currentContext != null) {
                GoRouter.of(MyApp.navigatorKey.currentContext!).push(route);
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ Error navigating from background tap: $e');
              }
            }
          });
        }
      },
      onError: (e) {
        if (kDebugMode) {
          debugPrint('❌ Error in onMessageOpenedApp: $e');
        }
      },
    );
  }

  @override
  void dispose() {
    _memoryCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_deepLinkInitialized) {
      DeepLinkHandler.dispose();
    }
    ImpressionBatcher().dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routerInitialized) {
      // ✅ JUST ONE LINE!
      _router = AppRouter.createRouter(
        navigatorKey: MyApp.navigatorKey,
        context: context,
      );
      _routerInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      // showPerformanceOverlay: true,
      title: 'Nar24',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router, // ✅ Use the router here
      locale: localeProvider.locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        if (child == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        try {
          final userProvider = Provider.of<UserProvider>(context);
          final marketProvider = Provider.of<MarketProvider>(context);

          final isLoading =
              (userProvider.isLoading || marketProvider.isLoading) ||
                  !_minSplashTimeElapsed;

          // Detect transition from loading to loaded (splash -> main app)
          final isTransitioningFromSplash = _wasLoadingLastFrame && !isLoading;

          // Update loading state for next frame
          if (_wasLoadingLastFrame != isLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _wasLoadingLastFrame = isLoading;
              }
            });
          }

          // Animated transition from splash to main app
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final childKey = child.key;

              // Splash screen - just fade out
              if (childKey == const ValueKey('splash_screen')) {
                return FadeTransition(opacity: animation, child: child);
              }

              // Main app - slide in from right (only on initial transition)
              if (childKey == const ValueKey('main_app') &&
                  isTransitioningFromSplash) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1.0, 0.0), // Start from right
                    end: Offset.zero, // End at center
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                );
              }

              // Default: just fade
              return FadeTransition(opacity: animation, child: child);
            },
            child: isLoading
                ? const KeyedSubtree(
                    key: ValueKey('splash_screen'),
                    child: VideoSplashScreen(),
                  )
                : KeyedSubtree(
                    key: const ValueKey('main_app'),
                    child: Builder(
                      builder: (innerContext) {
                        // ✅ NEW: Trigger version check when main app is shown
                        if (!_versionCheckCompleted &&
                            !_versionCheckInProgress) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _performVersionCheck(innerContext);
                          });
                        }
                        return child;
                      },
                    ),
                  ),
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error in app builder: $e');
          }
          return child;
        }
      },
    );
  }
}

class L10n {
  static final supportedLocales = [
    const Locale('tr'),
    const Locale('en'),
    const Locale('ru'),
  ];
}

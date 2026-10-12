import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'app_theme.dart';
import 'theme/app_theme.dart';
import 'models/procedure.dart';
import 'models/procedure_log.dart';
import 'screens/analysis_results_screen.dart';
import 'screens/ai_recovery_coach_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'screens/create_procedure_screen.dart';
import 'screens/home_screen.dart' show HomePage;
import 'screens/onboarding_screen.dart';
import 'screens/onboarding/skin_onboarding_screen.dart';
import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/features/ai_coach/presentation/screens/premium_recovery_hub_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/legal_screen.dart';
import 'screens/share_result_screen.dart';
import 'screens/welcome_tour_screen.dart';
import 'utils/app_prefs.dart';
import 'utils/premium_access.dart';
import 'utils/report_service.dart';
import 'utils/startup_guard.dart';
import 'services/notification_service.dart';
import 'widgets/paywall_screen.dart';
import 'widgets/premium_feature_sheet.dart';
import 'challenges/challenges_screen.dart';
import 'challenges/glow_up_challenge_screen.dart';
import 'challenges/year_end_challenge_screen.dart';
import 'screens/professional_report_screen.dart';
import 'screens/scar_healing_tracker_screen.dart';
import 'screens/peptide_tracker_screen.dart';
import 'screens/peptide_reconstitution_sheet.dart';
import 'screens/photo_gallery_screen.dart';
import 'screens/provider_notes_screen.dart';
import 'screens/product_store_screen.dart';
import 'screens/log_skincare_product_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/recovery_timeline_screen.dart';
import 'screens/procedure_history_screen.dart';
import 'screens/routines_screen.dart';
import 'screens/conversion_diagnostics_screen.dart';

// RouteObserver for HomePage refresh
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

/// Wraps the app so the entire widget tree can be rebuilt from scratch,
/// simulating an in-process restart. Used by the "Hard Reset" flow after
/// wiping all persisted data so the user immediately sees a clean state.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  /// Rebuilds the whole app tree. Call after clearing all persisted data.
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void restart() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Every step before runApp runs on the native launch screen, so each
      // one is bounded by runStartupStep: a step that throws or never
      // completes is logged and skipped instead of leaving the app stuck on
      // the splash screen.
      await runStartupStep('Hive.initFlutter', Hive.initFlutter);
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(ProcedureLogAdapter());
      }
      // Ensure the procedureLogs box is open on startup so the app always has
      // a valid box after a fresh launch or a Hard Reset restart.
      if (!Hive.isBoxOpen('procedureLogs')) {
        try {
          await Hive.openBox<ProcedureLog>('procedureLogs');
        } catch (e) {
          debugPrint('⚠️ Failed to open procedureLogs box on startup: $e');
        }
      }

      // Drop the pre-registry, device-global AI Skin Analysis baseline
      // cache -- it carried no procedureId/focusArea/poseTemplate/
      // guideType scoping, so a scan from one angle could silently become
      // "the baseline" compared against every future scan regardless of
      // angle or region. Never migrated into the new per-key registry
      // (see AppPrefs.setAiBaselineScanId) -- just dropped.
      unawaited(AppPrefs.clearLegacyAiManualBaselineMetricMatrix());

      final crashlyticsEnabled = await _initializeCrashlytics();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        if (crashlyticsEnabled) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
      };

      ui
          .PlatformDispatcher
          .instance
          .onError = (Object error, StackTrace stack) {
        if (crashlyticsEnabled) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        }
        return true;
      };

      ErrorWidget.builder = (FlutterErrorDetails details) {
        return _FriendlyAppErrorScreen(details: details);
      };

      // Warm scan history on startup so trend/delta UI always reads normalized data.
      await runStartupStep('scan history warm-up', () async {
        await AppPrefs.getScanEntries();
        await AppPrefs.getProcedureEntries();
        await AppPrefs.resolveActiveProcedureId();
        await AppPrefs.getUserProfilePictureOrNull();
        await AppPrefs.loadVerboseDiagnosticsSetting();
      });

      // Evict legacy oversized PDF blobs from localStorage to avoid
      // QuotaExceededError on subsequent report generation.
      await runStartupStep(
        'legacy report storage cleanup',
        ReportService.cleanupLegacyStorage,
      );

      // RevenueCat only works on mobile platforms, not on web.
      if (!kIsWeb) {
        try {
          const String iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
          const String androidKey = String.fromEnvironment(
            'REVENUECAT_ANDROID_KEY',
          );
          final String revenueCatPublicKey = Platform.isIOS
              ? iosKey
              : Platform.isAndroid
              ? androidKey
              : '';
          if (revenueCatPublicKey.isEmpty) {
            debugPrint(
              '[RevenueCat] Skipping Purchases.configure: no key supplied '
              'for this platform. Pass --dart-define=REVENUECAT_IOS_KEY=... '
              'or --dart-define=REVENUECAT_ANDROID_KEY=... to enable purchases.',
            );
          } else {
            PremiumAccess.revenueCatConfigured = await runStartupStep(
              'RevenueCat configure',
              () async {
                await Purchases.setLogLevel(LogLevel.debug);
                await Purchases.configure(
                  PurchasesConfiguration(revenueCatPublicKey),
                );
              },
            );
          }
        } catch (_) {
          // RevenueCat is mobile-only; app should still boot for local/web testing.
        }
      }

      runApp(
        RestartWidget(
          child: ProviderScope(
            child: AestheticSkinTracker(crashlyticsEnabled: crashlyticsEnabled),
          ),
        ),
      );

      // Opt-in reminders start after the first screen is up: the iOS
      // permission request can wait on a system dialog, which must never
      // hold the app on the launch screen.
      if (!kIsWeb) {
        unawaited(
          runStartupStep('notifications', () async {
            await NotificationService().initialize();
            if (await AppPrefs.getNotificationsEnabled()) {
              final granted = await NotificationService().requestPermissions();
              if (granted) {
                await NotificationService().resyncScheduledReminders();
              } else {
                await AppPrefs.setNotificationsEnabled(false);
              }
            }
          }, timeout: const Duration(minutes: 2)),
        );
      }
    },
    (Object error, StackTrace stack) async {
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          fatal: true,
        );
      } catch (_) {
        // Firebase/Crashlytics may be unavailable during local setup.
      }
    },
  );
}

Future<bool> _initializeCrashlytics() async {
  if (kIsWeb) {
    return false;
  }

  try {
    // Bounded so a Firebase setup that never answers can't hold the app on
    // the launch screen; a timeout is treated like Firebase being absent.
    await Firebase.initializeApp().timeout(defaultStartupStepTimeout);
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(true)
        .timeout(defaultStartupStepTimeout);
    return true;
  } catch (_) {
    // App should remain usable even when Firebase files are not configured yet.
    return false;
  }
}

class AestheticSkinTracker extends StatefulWidget {
  final bool crashlyticsEnabled;

  const AestheticSkinTracker({super.key, this.crashlyticsEnabled = false});

  @override
  State<AestheticSkinTracker> createState() => _AestheticSkinTrackerState();
}

class _AestheticSkinTrackerState extends State<AestheticSkinTracker> {
  static const Duration _routeTransitionDuration = Duration(milliseconds: 380);
  static const Duration _routeReverseTransitionDuration = Duration(
    milliseconds: 460,
  );

  @override
  void initState() {
    super.initState();
    MyApp.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    MyApp.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final page = _buildPageForRoute(settings);
    if (page == null) return null;

    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: _routeTransitionDuration,
      reverseTransitionDuration: _routeReverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final scale = Tween<double>(begin: 0.985, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }

  Widget? _buildPageForRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/home':
        return const HomePage();
      case '/first-run-protocol':
        return const FirstRunProtocolScreen();
      case '/paywall':
        return const PaywallScreen();
      case '/conversion-diagnostics':
        return const ConversionDiagnosticsScreen();
      case '/camera':
        return const CameraScreen(capturePurpose: CameraCapturePurpose.generic);
      case '/analysis':
        final args = settings.arguments as String?;
        return AnalysisResultsScreen(imagePath: args);
      case '/procedures':
      case '/custom-plans':
        return const ProcedureProfilesScreen();
      case '/premium-recovery':
        return const PremiumRecoveryHubScreen();
      case '/ai-recovery-coach':
        return const AIRecoveryCoachScreen();
      case '/ai-coach':
        return const SkinAiAnalysisScreen();
      case '/progress-analysis':
        // You may want a dedicated screen, but fallback to AnalysisResultsScreen for now
        return const AnalysisResultsScreen(imagePath: null);
      case '/scar-tracker':
        return const ScarHealingTrackerScreen();
      case '/create-procedure':
        return const CreateProcedureScreen();
      case '/procedure-history':
        return const PremiumRouteGate(child: ProcedureHistoryScreen());
      case '/routines':
        return const RoutinesScreen();
      case '/settings':
      case '/profile':
        return const SettingsScreen();
      case '/legal':
        return const LegalScreen();
      case '/onboarding':
        return const SkinOnboardingScreen();
      case '/legacy-onboarding':
        return const OnboardingFlowScreen();
      case '/welcome-tour':
        return const WelcomeTourScreen();
      case '/challenges':
        return const ChallengesScreen();
      case '/challenges/glowup':
        return GlowUpChallengeScreen(onChangeProcedure: () {});
      case '/challenges/yearend':
        return YearEndChallengeScreen(onChangeProcedure: () {});
      case '/peptide-tracker':
        final args = settings.arguments;
        final initialTab = args is Map && args['initialTab'] is num
            ? (args['initialTab'] as num).toInt()
            : null;
        return PeptideTrackerScreen(initialTab: initialTab);
      case '/peptide-library':
        return const PeptideTrackerScreen(initialTab: 3);
      case '/peptide-reconstitution':
        return const PeptideReconstitutionSheet();
      case '/gallery':
        return const PhotoGalleryScreen();
      case '/store':
        return const ProductStoreScreen();
      case '/log-skincare-product':
        return const LogSkincareProductScreen();
      case '/cart':
        return const CartScreen();
      case '/timeline':
        // Focused Recovery Timeline screen surfaced from the Recovery Hub.
        // Accepts an optional {procedureId} map argument so the active
        // procedure can be pre-selected.
        final args = settings.arguments;
        String? procId;
        if (args is Map) {
          procId = (args['procedureId'] as String?)?.trim();
          if (procId != null && procId.isEmpty) procId = null;
        }
        return RecoveryTimelineScreen(procedureId: procId);
      case '/provider-notes':
        // Dedicated clinical notes screen. Accepts an optional
        // {procedureId, procedureLabel} map argument so the hub card
        // can pre-scope the notes to the active procedure.
        final args = settings.arguments;
        String? procId;
        String? procLabel;
        if (args is Map) {
          procId = (args['procedureId'] as String?)?.trim();
          procLabel = (args['procedureLabel'] as String?)?.trim();
          if (procId != null && procId.isEmpty) procId = null;
          if (procLabel != null && procLabel.isEmpty) procLabel = null;
        }
        return ProviderNotesScreen(
          procedureId: procId,
          procedureLabel: procLabel,
        );
      case '/report':
        return const PremiumRouteGate(child: ProfessionalReportScreen());
      case '/share':
        return const PremiumRouteGate(child: ShareResultScreen());
      default:
        // Dynamic deep-link: /procedures/{id} → load + open detail.
        final name = settings.name ?? '';
        if (name.startsWith('/procedures/')) {
          final procId = name.substring('/procedures/'.length).trim();
          if (procId.isNotEmpty) {
            return _ProcedureDetailLoader(procedureId: procId);
          }
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'AestheticSkinTracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(context),
      darkTheme: AppTheme.dark(context),
      themeMode: MyApp.themeModeNotifier.value,
      home: const SplashScreen(),
      onGenerateRoute: _onGenerateRoute,
      onUnknownRoute: (settings) =>
          _onGenerateRoute(const RouteSettings(name: '/home'))!,
      navigatorObservers: [routeObserver], // ← Added for HomePage auto-refresh
    );

    return _CrashlyticsAppShell(
      crashlyticsEnabled: widget.crashlyticsEnabled,
      child: app,
    );
  }
}

class _CrashlyticsAppShell extends StatefulWidget {
  final bool crashlyticsEnabled;
  final Widget child;

  const _CrashlyticsAppShell({
    required this.crashlyticsEnabled,
    required this.child,
  });

  @override
  State<_CrashlyticsAppShell> createState() => _CrashlyticsAppShellState();
}

class _CrashlyticsAppShellState extends State<_CrashlyticsAppShell> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _FriendlyAppErrorScreen extends StatelessWidget {
  final FlutterErrorDetails details;

  const _FriendlyAppErrorScreen({required this.details});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.refinedSlate,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please restart the app. If this keeps happening, contact support.',
                    style: TextStyle(color: AppColors.refinedSlate),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: SingleChildScrollView(
                      child: Text(
                        details.exceptionAsString(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0x8A1E2225),
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
}

class _ProcedureDetailLoader extends StatefulWidget {
  const _ProcedureDetailLoader({required this.procedureId});
  final String procedureId;

  @override
  State<_ProcedureDetailLoader> createState() => _ProcedureDetailLoaderState();
}

class _ProcedureDetailLoaderState extends State<_ProcedureDetailLoader> {
  late final Future<Procedure?> _future = _load();

  Future<Procedure?> _load() async {
    final raw = await AppPrefs.getProcedureEntries();
    for (final e in raw) {
      final p = Procedure.fromJson(Map<String, dynamic>.from(e));
      if (p.id == widget.procedureId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Procedure?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final p = snap.data;
        if (p == null) {
          return const ProcedureProfilesScreen();
        }
        return ProcedureDetailScreen(procedure: p);
      },
    );
  }
}

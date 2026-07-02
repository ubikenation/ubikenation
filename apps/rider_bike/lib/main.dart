import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/rider_repository.dart';
import 'services/session_guard.dart';
import 'theme/app_theme.dart';
import 'widgets/connectivity_gate.dart';
import 'widgets/animated_splash.dart';
import 'screens/auth_screen.dart';
import 'screens/gate_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/call_screen.dart';

/// Global key so foreground push can show an in-app banner.
final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

/// Set at launch when the rider is returning after being away a while.
bool pendingWelcome = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Stay signed in across restarts; force a fresh sign-in after 48h idle.
  pendingWelcome = await SessionGuard.evaluate();

  final api = ApiClient();

  // Render the UI immediately. Push/Firebase init runs AFTER, in the background, so a
  // slow or missing FCM/Google-Play setup can never block startup (no black screen).
  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<ApiClient>.value(value: api),
        Provider<RiderRepository>(create: (_) => RiderRepository(api)),
      ],
      child: const RiderApp(),
    ),
  );

  _initPush(api);
}

/// Best-effort push setup, after the first frame so it never blocks the UI.
/// Riders get "new request" alerts; token registered after sign-in.
Future<void> _initPush(ApiClient api) async {
  final push = PushService(
    api,
    messengerKey: messengerKey,
    onOpen: (data) {
      if (data['type'] == 'incoming_call' && data['tripId'] is String) {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => CallScreen(
            tripId: data['tripId'] as String,
            peerName: (data['callerName'] as String?) ?? 'Caller',
            incoming: true,
          ),
        ));
      }
    },
  );
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    await push.init();
    if (Supabase.instance.client.auth.currentSession != null) {
      await push.registerToken();
    }
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null) push.registerToken();
    });
  } catch (_) {/* Firebase not configured / slow — push disabled, app still runs */}
}

class RiderApp extends StatefulWidget {
  const RiderApp({super.key});

  @override
  State<RiderApp> createState() => _RiderAppState();
}

class _RiderAppState extends State<RiderApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (pendingWelcome) {
      pendingWelcome = false;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (Supabase.instance.client.auth.currentSession != null) SessionGuard.showWelcome(messengerKey);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SessionGuard.evaluate().then((welcome) {
        if (welcome && Supabase.instance.client.auth.currentSession != null) {
          SessionGuard.showWelcome(messengerKey);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Piki',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light,
      home: const AnimatedSplash(next: ConnectivityGate(child: _AuthGate())),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<AuthState>(
      stream: auth.onAuthChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        return auth.isSignedIn ? const GateScreen() : const AuthScreen();
      },
    );
  }
}
